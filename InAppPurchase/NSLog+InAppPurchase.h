#import <Foundation/Foundation.h>
#import <StoreKit/StoreKit.h>

static char *SKPaymentTransactionStatesMap[] = {
        "SKPaymentTransactionStatePurchasing",
        "SKPaymentTransactionStatePurchased",
        "SKPaymentTransactionStateFailed",
        "SKPaymentTransactionStateRestored"
};

#pragma unused(SKPaymentTransactionStatesMap)

#define NSLogTransaction(transaction) \
    NSLog(@"Transaction:"); \
    NSLog(@" - Identifier: %@", transaction.transactionIdentifier); \
    NSLog(@" - Date: %@", transaction.transactionDate); \
    NSLog(@" - State: %s", SKPaymentTransactionStatesMap[transaction.transactionState]); \
    NSLog(@" - Receipt: %@", transaction.transactionReceipt); \
    NSLog(@"Payment:"); \
    NSLog(@" - Product Identifier: %@", transaction.payment.productIdentifier); \
    NSLog(@" - Quantity: %d", transaction.payment.quantity); \
    NSLog(@" - Request Data: %@", transaction.payment.requestData);

