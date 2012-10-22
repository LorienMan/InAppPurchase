#import <StoreKit/StoreKit.h>
#import "InAppPurchaseManager.h"
#import "InAppPurchaseProductActivator.h"
#import "InAppPurchaseAlertHandler.h"
#import "AlertViewAlertHandler.h"
#import "RRVerificationController.h"

@interface InAppPurchaseManager () <SKPaymentTransactionObserver, SKProductsRequestDelegate, RRVerificationControllerDelegate> {
    NSMutableArray *productActivators;

    SKProductsRequest *productsRequest;

    NSArray *products;

    NSString *sharedSecret;
}

@end

@implementation InAppPurchaseManager

@synthesize alertHandler = _alertHandler;


- (id)initWithSharedSecret:(NSString *)_secret {
    self = [super init];
    if (self) {
        sharedSecret = _secret;

        productActivators = [NSMutableArray new];

        self.alertHandler = [AlertViewAlertHandler new];

        [[SKPaymentQueue defaultQueue] addTransactionObserver:self];
    }
    return self;
}

- (void)addProductActivator:(id <InAppPurchaseProductActivator>)productActivator {
    [productActivators addObject:productActivator];
}

- (void)removeProductActivator:(id <InAppPurchaseProductActivator>)productActivator {
    [productActivators removeObject:productActivator];
}

- (void)updateProducts {
    NSMutableSet *productIdentifiers = [NSMutableSet new];

    for (id<InAppPurchaseProductActivator> purchaseActivator in productActivators) {
        [productIdentifiers addObject:purchaseActivator.productIdentifier];
    }

    productsRequest = [[SKProductsRequest alloc] initWithProductIdentifiers:productIdentifiers];
    productsRequest.delegate = self;
    [productsRequest start];

    [[NSNotificationCenter defaultCenter]
            postNotificationName:IN_APP_PURCHASE_PRODUCTS_UPDATE_STARTED_NOTIFICATION
                          object:nil];
}

- (BOOL)canMakePurchases {
    return [SKPaymentQueue canMakePayments];
}

- (SKProduct *)productByIdentifier:(NSString *)productIdentifier {
    NSArray *result = [products filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"productIdentifier == %@", productIdentifier]];
    return result.count ? [result objectAtIndex:0] : nil;
}

- (void)purchaseProduct:(NSString *)productIdentifier {
    SKProduct *product = [self productByIdentifier:productIdentifier];

    if (product) {
        SKPayment *payment = [SKPayment paymentWithProduct:product];

        [[SKPaymentQueue defaultQueue] addPayment:payment];

        [[NSNotificationCenter defaultCenter]
                postNotificationName:IN_APP_PURCHASE_STARTED_NOTIFICATION
                              object:nil];
    } else {
        NSLog(@"[InAppPurchase] %@ Can't find product identifier in updated products. Possible updateProducts method isn't called.", productIdentifier);
        [self.alertHandler showError:L(@"product-not-found")];
    }
}

#pragma mark SKRequest Handlers

- (void)productsRequest:(SKProductsRequest *)request didReceiveResponse:(SKProductsResponse *)response {
    products = response.products;

    if (response.invalidProductIdentifiers.count != 0) {
        NSLog(@"[InAppPurchase] - Some products has unknown or invalid product identifiers: ");
        for (NSString *productIdentifier in response.invalidProductIdentifiers) {
            NSLog(@"[InAppPurchase] -  * %@", productIdentifier);
        }

        [self.alertHandler showWarning:L(@"invalid-products")];
    }

    [[NSNotificationCenter defaultCenter]
            postNotificationName:IN_APP_PURCHASE_PRODUCTS_UPDATE_SUCCESS_NOTIFICATION
                          object:nil];
}

- (void)request:(SKRequest *)request didFailWithError:(NSError *)error {
    NSLog(@"[InAppPurchase] - Can't update products from iTunesConnect: %@", error);
    [self.alertHandler showError:[NSString stringWithFormat:L(@"product-list-unavailable"), error.localizedDescription]];

    [[NSNotificationCenter defaultCenter]
            postNotificationName:IN_APP_PURCHASE_PRODUCTS_UPDATE_FAILED_NOTIFICATION
                          object:nil];
}

- (void)requestDidFinish:(SKRequest *)request {
    [[NSNotificationCenter defaultCenter]
            postNotificationName:IN_APP_PURCHASE_PRODUCTS_UPDATE_FINISHED_NOTIFICATION
                          object:nil];
}

#pragma mark SKPaymentQueue Handlers

- (void)paymentQueue:(SKPaymentQueue *)queue updatedTransactions:(NSArray *)transactions {
    [RRVerificationController sharedInstance].itcContentProviderSharedSecret = sharedSecret;

    for (SKPaymentTransaction *transaction in transactions) {
        switch ([transaction transactionState]) {
            case SKPaymentTransactionStatePurchasing:
                break;
            case SKPaymentTransactionStatePurchased:
            case SKPaymentTransactionStateRestored:
                // If verification is successful, the delegate's verificationControllerDidVerifyPurchase:isValid: method
                // will be called to take appropriate action and complete the transaction
                if (![[RRVerificationController sharedInstance] verifyPurchase:transaction
                                                                  withDelegate:self
                                                                         error:nil]) {
                    [self failedTransaction:transaction];
                }
                break;
            case SKPaymentTransactionStateFailed:
                [self failedTransaction:transaction];
                break;
            default:
                break;
        }
    }
}

- (void)completeTransaction:(SKPaymentTransaction *)transaction {
    BOOL result = [self provideContent:transaction withProductIdentifier:transaction.payment.productIdentifier];
    [self finishTransaction:transaction wasSuccessful:result];
}

- (void)restoreTransaction:(SKPaymentTransaction *)transaction {
    BOOL result = [self provideContent:transaction withProductIdentifier:transaction.originalTransaction.payment.productIdentifier];
    [self finishTransaction:transaction wasSuccessful:result];
}

- (void)failedTransaction:(SKPaymentTransaction *)transaction {
    [self finishTransaction:transaction wasSuccessful:NO];
}

- (id <InAppPurchaseProductActivator>)productActivatorByProductIdentifier:(NSString *)productIdentifier {
    NSArray *result = [productActivators filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"productIdentifier == %@", productIdentifier]];
    return result.count ? [result objectAtIndex:0] : nil;
}

- (BOOL)provideContent:(SKPaymentTransaction *)transaction withProductIdentifier:(NSString *)productIdentifier {
    BOOL result = NO;

    id <InAppPurchaseProductActivator> productActivator = [self productActivatorByProductIdentifier:productIdentifier];

    if (productActivator) {
        BOOL productActivatorResult = [productActivator activateProduct:transaction];

        if (productActivatorResult) {
            result = YES;
        } else {
            NSLog(@"[InAppPurchase] %@ Can't activate purchased product.", productIdentifier);
            [self.alertHandler showError:L(@"can-not-activate-product")];
        }
    } else {
        NSLog(@"[InAppPurchase] %@ Can't find product activator.", productIdentifier);
        [self.alertHandler showError:L(@"product-activator-not-found")];
    }

    return result;
}

- (void)finishTransaction:(SKPaymentTransaction *)transaction wasSuccessful:(BOOL)wasSuccessful {
    if (wasSuccessful) {
        [[SKPaymentQueue defaultQueue] finishTransaction:transaction];

        [[NSNotificationCenter defaultCenter]
                postNotificationName:IN_APP_PURCHASE_PAYMENT_SUCCESS_NOTIFICATION
                              object:nil];

    } else {
        NSString *productIdentifier = transaction.payment.productIdentifier;

        switch (transaction.error.code) {
            case SKErrorUnknown:
                NSLog(@"[InAppPurchase] %@ Unknown error: %@", productIdentifier, transaction.error);
                [self.alertHandler showError:[NSString stringWithFormat:@"%@.", transaction.error.localizedDescription]];
                break;
            case SKErrorClientInvalid:       // client is not allowed to issue the request, etc.
                NSLog(@"[InAppPurchase] %@ Client is not allowed to perform purchase request.", productIdentifier);
                [self.alertHandler showError:L(@"client-invalid-error")];
                break;
            case SKErrorPaymentCancelled:    // user cancelled the request, etc.
                NSLog(@"[InAppPurchase] %@ Purchase canceled.", productIdentifier);
                break;
            case SKErrorPaymentInvalid:      // purchase identifier was invalid, etc.
                NSLog(@"[InAppPurchase] %@ Purchase identifier was invalid.", productIdentifier);
                [self.alertHandler showError:L(@"payment-invalid-error")];
                break;
            case SKErrorPaymentNotAllowed:   // this device is not allowed to make the payment
                NSLog(@"[InAppPurchase] %@ This device is not allowed to make the payment.", productIdentifier);
                [self.alertHandler showError:L(@"payment-not-allowed-error")];
                break;
            default:
                break;
        }

        [[SKPaymentQueue defaultQueue] finishTransaction:transaction];

        [[NSNotificationCenter defaultCenter]
                postNotificationName:IN_APP_PURCHASE_PAYMENT_FAIL_NOTIFICATION
                              object:nil];
    }

    [[NSNotificationCenter defaultCenter]
            postNotificationName:IN_APP_PURCHASE_FINISHED_NOTIFICATION
                          object:nil];
}

#pragma mark RRVerificationControllerDelegate

- (void)verificationControllerDidVerifyPurchase:(SKPaymentTransaction *)transaction isValid:(BOOL)isValid {
    if (isValid) {
        switch (transaction.transactionState) {
            case SKPaymentTransactionStatePurchased:
                [self completeTransaction:transaction];
                break;
            case SKPaymentTransactionStateRestored:
                [self restoreTransaction:transaction];
            default:
                break;
        }
    } else
        [self failedTransaction:transaction];
}

- (void)verificationControllerDidFailToVerifyPurchase:(SKPaymentTransaction *)transaction error:(NSError *)error {
    // This transaction is supposed to be failed, because we failed to verify it's receipt.
    // In this case we MUST ask user to restore transactions, because the product might be really purchased.
    [self.alertHandler showError:L(@"payment-not-verified-error")];
    [[SKPaymentQueue defaultQueue] finishTransaction:transaction];

    [[NSNotificationCenter defaultCenter]
            postNotificationName:IN_APP_PURCHASE_PAYMENT_VERIFY_FAIL_NOTIFICATION
                          object:nil];
}

@end
