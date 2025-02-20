// Copyright 2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "CloudFirestorePlugin.h"
#import "UserAgent.h"

#import <Firebase/Firebase.h>

static FlutterError *getFlutterError(NSError *error) {
  if (error == nil) return nil;

  return [FlutterError errorWithCode:[NSString stringWithFormat:@"Error %ld", (long)error.code]
                             message:error.domain
                             details:error.localizedDescription];
}

static FIRFirestore *getFirestore(NSDictionary *arguments) {
  FIRApp *app = [FIRApp appNamed:arguments[@"app"]];
  return [FIRFirestore firestoreForApp:app];
}

static FIRDocumentReference *getDocumentReference(NSDictionary *arguments) {
  return [getFirestore(arguments) documentWithPath:arguments[@"path"]];
}

static NSArray *getDocumentValues(NSDictionary *document, NSArray *orderBy,
                                  BOOL isCollectionGroup) {
  NSMutableArray *values = [[NSMutableArray alloc] init];
  NSDictionary *documentData = document[@"data"];
  if (orderBy) {
    for (id item in orderBy) {
      NSArray *orderByParameters = item;
      NSObject *field = orderByParameters[0];

      if ([field isKindOfClass:[FIRFieldPath class]]) {
        if ([field isEqual:FIRFieldPath.documentID]) {
          // This is also checked by an assertion on the Dart side.
          [NSException
               raise:@"Invalid use of FieldValue.documentId"
              format:
                  @"You cannot order by the document id when using "
                   "{start/end}{At/After/Before}Document as the library will order by the document"
                   " id implicitly in order to to add other fields to the order clause."];
        } else {
          // Unsupported type.
        }
      } else if ([field isKindOfClass:[NSString class]]) {
        NSString *fieldName = orderByParameters[0];
        if ([fieldName rangeOfString:@"."].location != NSNotFound) {
          NSArray *fieldNameParts = [fieldName componentsSeparatedByString:@"."];
          NSDictionary *currentMap = [documentData objectForKey:[fieldNameParts objectAtIndex:0]];
          for (int i = 1; i < [fieldNameParts count] - 1; i++) {
            currentMap = [currentMap objectForKey:[fieldNameParts objectAtIndex:i]];
          }
          [values
              addObject:[currentMap objectForKey:[fieldNameParts
                                                     objectAtIndex:[fieldNameParts count] - 1]]];
        } else {
          [values addObject:[documentData objectForKey:fieldName]];
        }
      } else {
        // Invalid type.
      }
    }
  }
  if (isCollectionGroup) {
    NSString *path = document[@"path"];
    [values addObject:path];
  } else {
    NSString *documentId = document[@"id"];
    [values addObject:documentId];
  }
  return values;
}

static FIRQuery *getQuery(NSDictionary *arguments) {
  NSNumber *data = arguments[@"isCollectionGroup"];
  BOOL isCollectionGroup = data.boolValue;
  FIRQuery *query;
  if (isCollectionGroup) {
    query = [getFirestore(arguments) collectionGroupWithID:arguments[@"path"]];
  } else {
    query = [getFirestore(arguments) collectionWithPath:arguments[@"path"]];
  }
  NSDictionary *parameters = arguments[@"parameters"];
  NSArray *whereConditions = parameters[@"where"];
  for (id item in whereConditions) {
    NSArray *condition = item;

    FIRFieldPath *fieldPath = nil;
    NSString *fieldName = nil;
    NSObject *field = condition[0];

    if ([field isKindOfClass:[NSString class]]) {
      fieldName = (NSString *)field;
    } else if ([field isKindOfClass:[FIRFieldPath class]]) {
      fieldPath = (FIRFieldPath *)field;
    } else {
      // Invalid type.
    }

    NSString *op = condition[1];
    id value = condition[2];
    if ([op isEqualToString:@"=="]) {
      if (fieldName != nil) {
        query = [query queryWhereField:fieldName isEqualTo:value];
      } else if (fieldPath != nil) {
        query = [query queryWhereFieldPath:fieldPath isEqualTo:value];
      } else {
        // Invalid type.
      }
    } else if ([op isEqualToString:@"<"]) {
      if (fieldName != nil) {
        query = [query queryWhereField:fieldName isLessThan:value];
      } else if (fieldPath != nil) {
        query = [query queryWhereFieldPath:fieldPath isLessThan:value];
      } else {
        // Invalid type.
      }
    } else if ([op isEqualToString:@"<="]) {
      if (fieldName != nil) {
        query = [query queryWhereField:fieldName isLessThanOrEqualTo:value];
      } else if (fieldPath != nil) {
        query = [query queryWhereFieldPath:fieldPath isLessThanOrEqualTo:value];
      } else {
        // Invalid type.
      }
    } else if ([op isEqualToString:@">"]) {
      if (fieldName != nil) {
        query = [query queryWhereField:fieldName isGreaterThan:value];
      } else if (fieldPath != nil) {
        query = [query queryWhereFieldPath:fieldPath isGreaterThan:value];
      } else {
        // Invalid type.
      }
    } else if ([op isEqualToString:@">="]) {
      if (fieldName != nil) {
        query = [query queryWhereField:fieldName isGreaterThanOrEqualTo:value];
      } else if (fieldPath != nil) {
        query = [query queryWhereFieldPath:fieldPath isGreaterThanOrEqualTo:value];
      } else {
        // Invalid type.
      }
    } else if ([op isEqualToString:@"array-contains"]) {
      if (fieldName != nil) {
        query = [query queryWhereField:fieldName arrayContains:value];
      } else if (fieldPath != nil) {
        query = [query queryWhereFieldPath:fieldPath arrayContains:value];
      } else {
        // Invalid type.
      }
    } else {
      // Unsupported operator
    }
  }
  id limit = parameters[@"limit"];
  if (limit) {
    NSNumber *length = limit;
    query = [query queryLimitedTo:[length intValue]];
  }
  NSArray *orderBy = parameters[@"orderBy"];
  if (orderBy) {
    for (NSArray *orderByParameters in orderBy) {
      FIRFieldPath *fieldPath = nil;
      NSString *fieldName = nil;
      NSObject *field = orderByParameters[0];
      if ([field isKindOfClass:[NSString class]]) {
        fieldName = (NSString *)field;
      } else if ([field isKindOfClass:[FIRFieldPath class]]) {
        fieldPath = (FIRFieldPath *)field;
      } else {
        // Invalid type.
      }

      NSNumber *descending = orderByParameters[1];

      if (fieldName != nil) {
        query = [query queryOrderedByField:fieldName descending:[descending boolValue]];
      } else if (fieldPath != nil) {
        query = [query queryOrderedByFieldPath:fieldPath descending:[descending boolValue]];
      } else {
        // Invalid type.
      }
    }
  }
  id startAt = parameters[@"startAt"];
  if (startAt) {
    NSArray *startAtValues = startAt;
    query = [query queryStartingAtValues:startAtValues];
  }
  id startAtDocument = parameters[@"startAtDocument"];
  id startAfterDocument = parameters[@"startAfterDocument"];
  id endAtDocument = parameters[@"endAtDocument"];
  id endBeforeDocument = parameters[@"endBeforeDocument"];
  if (startAtDocument || startAfterDocument || endAtDocument || endBeforeDocument) {
    if ([orderBy count] == 0) {
      [NSException raise:@"No order by clause specified"
                  format:@"You need to order by at least one field when using {start/end}{At/"
                          "After/Before}Document as you need some value to e.g. start after."];
    }
    NSArray *orderByParameters = [orderBy lastObject];
    NSNumber *descending = orderByParameters[1];
    query = [query queryOrderedByFieldPath:FIRFieldPath.documentID
                                descending:[descending boolValue]];
  }
  if (startAtDocument) {
    query = [query
        queryStartingAtValues:getDocumentValues(startAtDocument, orderBy, isCollectionGroup)];
  }
  id startAfter = parameters[@"startAfter"];
  if (startAfter) {
    NSArray *startAfterValues = startAfter;
    query = [query queryStartingAfterValues:startAfterValues];
  }
  if (startAfterDocument) {
    query = [query
        queryStartingAfterValues:getDocumentValues(startAfterDocument, orderBy, isCollectionGroup)];
  }
  id endAt = parameters[@"endAt"];
  if (endAt) {
    NSArray *endAtValues = endAt;
    query = [query queryEndingAtValues:endAtValues];
  }
  if (endAtDocument) {
    query =
        [query queryEndingAtValues:getDocumentValues(endAtDocument, orderBy, isCollectionGroup)];
  }
  id endBefore = parameters[@"endBefore"];
  if (endBefore) {
    NSArray *endBeforeValues = endBefore;
    query = [query queryEndingBeforeValues:endBeforeValues];
  }
  if (endBeforeDocument) {
    query = [query
        queryEndingBeforeValues:getDocumentValues(endBeforeDocument, orderBy, isCollectionGroup)];
  }
  return query;
}

static FIRFirestoreSource getSource(NSDictionary *arguments) {
  NSString *source = arguments[@"source"];
  if ([@"server" isEqualToString:source]) {
    return FIRFirestoreSourceServer;
  }
  if ([@"cache" isEqualToString:source]) {
    return FIRFirestoreSourceCache;
  }
  return FIRFirestoreSourceDefault;
}

static NSDictionary *parseQuerySnapshot(FIRQuerySnapshot *snapshot) {
  NSMutableArray *paths = [NSMutableArray array];
  NSMutableArray *documents = [NSMutableArray array];
  NSMutableArray *metadatas = [NSMutableArray array];
  for (FIRDocumentSnapshot *document in snapshot.documents) {
    [paths addObject:document.reference.path];
    [documents addObject:document.data];
    [metadatas addObject:@{
      @"hasPendingWrites" : @(document.metadata.hasPendingWrites),
      @"isFromCache" : @(document.metadata.isFromCache),
    }];
  }
  NSMutableArray *documentChanges = [NSMutableArray array];
  for (FIRDocumentChange *documentChange in snapshot.documentChanges) {
    NSString *type;
    switch (documentChange.type) {
      case FIRDocumentChangeTypeAdded:
        type = @"DocumentChangeType.added";
        break;
      case FIRDocumentChangeTypeModified:
        type = @"DocumentChangeType.modified";
        break;
      case FIRDocumentChangeTypeRemoved:
        type = @"DocumentChangeType.removed";
        break;
    }
    [documentChanges addObject:@{
      @"type" : type,
      @"document" : documentChange.document.data,
      @"path" : documentChange.document.reference.path,
      @"oldIndex" : [NSNumber numberWithUnsignedInteger:documentChange.oldIndex],
      @"newIndex" : [NSNumber numberWithUnsignedInteger:documentChange.newIndex],
      @"metadata" : @{
        @"hasPendingWrites" : @(documentChange.document.metadata.hasPendingWrites),
        @"isFromCache" : @(documentChange.document.metadata.isFromCache),
      },
    }];
  }
  return @{
    @"paths" : paths,
    @"documentChanges" : documentChanges,
    @"documents" : documents,
    @"metadatas" : metadatas,
    @"metadata" : @{
      @"hasPendingWrites" : @(snapshot.metadata.hasPendingWrites),
      @"isFromCache" : @(snapshot.metadata.isFromCache),
    }
  };
}

const UInt8 DATE_TIME = 128;
const UInt8 GEO_POINT = 129;
const UInt8 DOCUMENT_REFERENCE = 130;
const UInt8 BLOB = 131;
const UInt8 ARRAY_UNION = 132;
const UInt8 ARRAY_REMOVE = 133;
const UInt8 DELETE = 134;
const UInt8 SERVER_TIMESTAMP = 135;
const UInt8 TIMESTAMP = 136;
const UInt8 INCREMENT_DOUBLE = 137;
const UInt8 INCREMENT_INTEGER = 138;
const UInt8 DOCUMENT_ID = 139;

@interface FirestoreWriter : FlutterStandardWriter
- (void)writeValue:(id)value;
@end

@implementation FirestoreWriter : FlutterStandardWriter
- (void)writeValue:(id)value {
  if ([value isKindOfClass:[NSDate class]]) {
    [self writeByte:DATE_TIME];
    NSDate *date = value;
    NSTimeInterval time = date.timeIntervalSince1970;
    SInt64 ms = (SInt64)(time * 1000.0);
    [self writeBytes:&ms length:8];
  } else if ([value isKindOfClass:[FIRTimestamp class]]) {
    FIRTimestamp *timestamp = value;
    SInt64 seconds = timestamp.seconds;
    int nanoseconds = timestamp.nanoseconds;
    [self writeByte:TIMESTAMP];
    [self writeBytes:(UInt8 *)&seconds length:8];
    [self writeBytes:(UInt8 *)&nanoseconds length:4];
  } else if ([value isKindOfClass:[FIRGeoPoint class]]) {
    FIRGeoPoint *geoPoint = value;
    Float64 latitude = geoPoint.latitude;
    Float64 longitude = geoPoint.longitude;
    [self writeByte:GEO_POINT];
    [self writeAlignment:8];
    [self writeBytes:(UInt8 *)&latitude length:8];
    [self writeBytes:(UInt8 *)&longitude length:8];
  } else if ([value isKindOfClass:[FIRDocumentReference class]]) {
    FIRDocumentReference *document = value;
    NSString *documentPath = [document path];
    [self writeByte:DOCUMENT_REFERENCE];
    [self writeUTF8:document.firestore.app.name];
    [self writeUTF8:documentPath];
  } else if ([value isKindOfClass:[NSData class]]) {
    NSData *blob = value;
    [self writeByte:BLOB];
    [self writeSize:(UInt32)blob.length];
    [self writeData:blob];
  } else {
    [super writeValue:value];
  }
}
@end

@interface FirestoreReader : FlutterStandardReader
- (id)readValueOfType:(UInt8)type;
@end

@implementation FirestoreReader
- (id)readValueOfType:(UInt8)type {
  switch (type) {
    case DATE_TIME: {
      SInt64 value;
      [self readBytes:&value length:8];
      return [NSDate dateWithTimeIntervalSince1970:(value / 1000.0)];
    }
    case TIMESTAMP: {
      SInt64 seconds;
      int nanoseconds;
      [self readBytes:&seconds length:8];
      [self readBytes:&nanoseconds length:4];
      return [[FIRTimestamp alloc] initWithSeconds:seconds nanoseconds:nanoseconds];
    }
    case GEO_POINT: {
      Float64 latitude;
      Float64 longitude;
      [self readAlignment:8];
      [self readBytes:&latitude length:8];
      [self readBytes:&longitude length:8];
      return [[FIRGeoPoint alloc] initWithLatitude:latitude longitude:longitude];
    }
    case DOCUMENT_REFERENCE: {
      NSString *appName = [self readUTF8];
      FIRFirestore *firestore = [FIRFirestore firestoreForApp:[FIRApp appNamed:appName]];
      NSString *documentPath = [self readUTF8];
      return [firestore documentWithPath:documentPath];
    }
    case BLOB: {
      UInt32 elementCount = [self readSize];
      return [self readData:elementCount];
    }
    case ARRAY_UNION: {
      return [FIRFieldValue fieldValueForArrayUnion:[self readValue]];
    }
    case ARRAY_REMOVE: {
      return [FIRFieldValue fieldValueForArrayRemove:[self readValue]];
    }
    case DELETE: {
      return [FIRFieldValue fieldValueForDelete];
    }
    case SERVER_TIMESTAMP: {
      return [FIRFieldValue fieldValueForServerTimestamp];
    }
    case INCREMENT_DOUBLE: {
      NSNumber *value = [self readValue];
      return [FIRFieldValue fieldValueForDoubleIncrement:value.doubleValue];
    }
    case INCREMENT_INTEGER: {
      NSNumber *value = [self readValue];
      return [FIRFieldValue fieldValueForIntegerIncrement:value.intValue];
    }
    case DOCUMENT_ID: {
      return [FIRFieldPath documentID];
    }
    default:
      return [super readValueOfType:type];
  }
}
@end

@interface FirestoreReaderWriter : FlutterStandardReaderWriter
- (FlutterStandardWriter *)writerWithData:(NSMutableData *)data;
- (FlutterStandardReader *)readerWithData:(NSData *)data;
@end

@implementation FirestoreReaderWriter
- (FlutterStandardWriter *)writerWithData:(NSMutableData *)data {
  return [[FirestoreWriter alloc] initWithData:data];
}
- (FlutterStandardReader *)readerWithData:(NSData *)data {
  return [[FirestoreReader alloc] initWithData:data];
}
@end

@interface FLTCloudFirestorePlugin ()
@property(nonatomic, retain) FlutterMethodChannel *channel;
@end

@implementation FLTCloudFirestorePlugin {
  NSMutableDictionary<NSNumber *, id<FIRListenerRegistration>> *_listeners;
  int _nextListenerHandle;
  NSMutableDictionary *transactions;
  NSMutableDictionary *transactionResults;
  NSMutableDictionary<NSNumber *, FIRWriteBatch *> *_batches;
  int _nextBatchHandle;
}

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  FirestoreReaderWriter *firestoreReaderWriter = [FirestoreReaderWriter new];
  FlutterMethodChannel *channel =
      [FlutterMethodChannel methodChannelWithName:@"plugins.flutter.io/cloud_firestore"
                                  binaryMessenger:[registrar messenger]
                                            codec:[FlutterStandardMethodCodec
                                                      codecWithReaderWriter:firestoreReaderWriter]];
  FLTCloudFirestorePlugin *instance = [[FLTCloudFirestorePlugin alloc] init];
  instance.channel = channel;
  [registrar addMethodCallDelegate:instance channel:channel];

  SEL sel = NSSelectorFromString(@"registerLibrary:withVersion:");
  if ([FIRApp respondsToSelector:sel]) {
    [FIRApp performSelector:sel withObject:LIBRARY_NAME withObject:LIBRARY_VERSION];
  }
}

- (instancetype)init {
  self = [super init];
  if (self) {
    if (![FIRApp appNamed:@"__FIRAPP_DEFAULT"]) {
      NSLog(@"Configuring the default Firebase app...");
      [FIRApp configure];
      NSLog(@"Configured the default Firebase app %@.", [FIRApp defaultApp].name);
    }
    _listeners = [NSMutableDictionary<NSNumber *, id<FIRListenerRegistration>> dictionary];
    _batches = [NSMutableDictionary<NSNumber *, FIRWriteBatch *> dictionary];
    _nextListenerHandle = 0;
    _nextBatchHandle = 0;
    transactions = [NSMutableDictionary<NSNumber *, FIRTransaction *> dictionary];
    transactionResults = [NSMutableDictionary<NSNumber *, id> dictionary];
  }
  return self;
}

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
  __weak __typeof__(self) weakSelf = self;
  void (^defaultCompletionBlock)(NSError *) = ^(NSError *error) {
    result(getFlutterError(error));
  };
  if ([@"Firestore#runTransaction" isEqualToString:call.method]) {
    [getFirestore(call.arguments)
        runTransactionWithBlock:^id(FIRTransaction *transaction, NSError **pError) {
          NSNumber *transactionId = call.arguments[@"transactionId"];
          NSNumber *transactionTimeout = call.arguments[@"transactionTimeout"];

          self->transactions[transactionId] = transaction;

          dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

          [weakSelf.channel invokeMethod:@"DoTransaction"
                               arguments:call.arguments
                                  result:^(id doTransactionResult) {
                                    FLTCloudFirestorePlugin *currentSelf = weakSelf;
                                    currentSelf->transactionResults[transactionId] =
                                        doTransactionResult;
                                    dispatch_semaphore_signal(semaphore);
                                  }];

          dispatch_semaphore_wait(
              semaphore,
              dispatch_time(DISPATCH_TIME_NOW, [transactionTimeout integerValue] * 1000000));

          return self->transactionResults[transactionId];
        }
        completion:^(id transactionResult, NSError *error) {
          if (error != nil) {
            result([FlutterError errorWithCode:[NSString stringWithFormat:@"%ld", (long)error.code]
                                       message:error.localizedDescription
                                       details:nil]);
          }
          result(transactionResult);
        }];
  } else if ([@"Transaction#get" isEqualToString:call.method]) {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
      NSNumber *transactionId = call.arguments[@"transactionId"];
      FIRDocumentReference *document = getDocumentReference(call.arguments);
      FIRTransaction *transaction = self->transactions[transactionId];
      NSError *error = [[NSError alloc] init];

      FIRDocumentSnapshot *snapshot = [transaction getDocument:document error:&error];

      if (error != nil) {
        result([FlutterError errorWithCode:[NSString stringWithFormat:@"%tu", [error code]]
                                   message:[error localizedDescription]
                                   details:nil]);
      } else if (snapshot != nil) {
        result(@{
          @"path" : snapshot.reference.path,
          @"data" : snapshot.exists ? snapshot.data : [NSNull null],
          @"metadata" : @{
            @"hasPendingWrites" : @(snapshot.metadata.hasPendingWrites),
            @"isFromCache" : @(snapshot.metadata.isFromCache),
          },
        });
      } else {
        result(nil);
      }
    });
  } else if ([@"Transaction#update" isEqualToString:call.method]) {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
      NSNumber *transactionId = call.arguments[@"transactionId"];
      FIRDocumentReference *document = getDocumentReference(call.arguments);
      FIRTransaction *transaction = self->transactions[transactionId];

      [transaction updateData:call.arguments[@"data"] forDocument:document];
      result(nil);
    });
  } else if ([@"Transaction#set" isEqualToString:call.method]) {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
      NSNumber *transactionId = call.arguments[@"transactionId"];
      FIRDocumentReference *document = getDocumentReference(call.arguments);
      FIRTransaction *transaction = self->transactions[transactionId];

      [transaction setData:call.arguments[@"data"] forDocument:document];
      result(nil);
    });
  } else if ([@"Transaction#delete" isEqualToString:call.method]) {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
      NSNumber *transactionId = call.arguments[@"transactionId"];
      FIRDocumentReference *document = getDocumentReference(call.arguments);
      FIRTransaction *transaction = self->transactions[transactionId];

      [transaction deleteDocument:document];
      result(nil);
    });
  } else if ([@"DocumentReference#setData" isEqualToString:call.method]) {
    NSDictionary *options = call.arguments[@"options"];
    FIRDocumentReference *document = getDocumentReference(call.arguments);
    if (![options isEqual:[NSNull null]] &&
        [options[@"merge"] isEqual:[NSNumber numberWithBool:YES]]) {
      [document setData:call.arguments[@"data"] merge:YES completion:defaultCompletionBlock];
    } else {
      [document setData:call.arguments[@"data"] completion:defaultCompletionBlock];
    }
  } else if ([@"DocumentReference#updateData" isEqualToString:call.method]) {
    FIRDocumentReference *document = getDocumentReference(call.arguments);
    [document updateData:call.arguments[@"data"] completion:defaultCompletionBlock];
  } else if ([@"DocumentReference#delete" isEqualToString:call.method]) {
    FIRDocumentReference *document = getDocumentReference(call.arguments);
    [document deleteDocumentWithCompletion:defaultCompletionBlock];
  } else if ([@"DocumentReference#get" isEqualToString:call.method]) {
    FIRDocumentReference *document = getDocumentReference(call.arguments);
    FIRFirestoreSource source = getSource(call.arguments);
    [document
        getDocumentWithSource:source
                   completion:^(FIRDocumentSnapshot *_Nullable snapshot, NSError *_Nullable error) {
                     if (snapshot == nil) {
                       result(getFlutterError(error));
                     } else {
                       result(@{
                         @"path" : snapshot.reference.path,
                         @"data" : snapshot.exists ? snapshot.data : [NSNull null],
                         @"metadata" : @{
                           @"hasPendingWrites" : @(snapshot.metadata.hasPendingWrites),
                           @"isFromCache" : @(snapshot.metadata.isFromCache),
                         },
                       });
                     }
                   }];
  } else if ([@"Query#addSnapshotListener" isEqualToString:call.method]) {
    __block NSNumber *handle = [NSNumber numberWithInt:_nextListenerHandle++];
    FIRQuery *query;
    @try {
      query = getQuery(call.arguments);
    } @catch (NSException *exception) {
      result([FlutterError errorWithCode:@"invalid_query"
                                 message:[exception name]
                                 details:[exception reason]]);
    }
    NSNumber *includeMetadataChanges = call.arguments[@"includeMetadataChanges"];
    id<FIRListenerRegistration> listener = [query
        addSnapshotListenerWithIncludeMetadataChanges:includeMetadataChanges.boolValue
                                             listener:^(FIRQuerySnapshot *_Nullable snapshot,
                                                        NSError *_Nullable error) {
                                               if (snapshot == nil) {
                                                 result(getFlutterError(error));
                                                 return;
                                               }
                                               NSMutableDictionary *arguments =
                                                   [parseQuerySnapshot(snapshot) mutableCopy];
                                               [arguments setObject:handle forKey:@"handle"];
                                               [weakSelf.channel invokeMethod:@"QuerySnapshot"
                                                                    arguments:arguments];
                                             }];
    _listeners[handle] = listener;
    result(handle);
  } else if ([@"DocumentReference#addSnapshotListener" isEqualToString:call.method]) {
    __block NSNumber *handle = [NSNumber numberWithInt:_nextListenerHandle++];
    FIRDocumentReference *document = getDocumentReference(call.arguments);
    NSNumber *includeMetadataChanges = call.arguments[@"includeMetadataChanges"];
    id<FIRListenerRegistration> listener = [document
        addSnapshotListenerWithIncludeMetadataChanges:includeMetadataChanges.boolValue
                                             listener:^(FIRDocumentSnapshot *snapshot,
                                                        NSError *_Nullable error) {
                                               if (snapshot == nil) {
                                                 result(getFlutterError(error));
                                                 return;
                                               }
                                               [weakSelf.channel
                                                   invokeMethod:@"DocumentSnapshot"
                                                      arguments:@{
                                                        @"handle" : handle,
                                                        @"path" : snapshot ? snapshot.reference.path
                                                                           : [NSNull null],
                                                        @"data" : snapshot.exists ? snapshot.data
                                                                                  : [NSNull null],
                                                        @"metadata" : snapshot ? @{
                                                          @"hasPendingWrites" :
                                                              @(snapshot.metadata.hasPendingWrites),
                                                          @"isFromCache" :
                                                              @(snapshot.metadata.isFromCache),
                                                        }
                                                                               : [NSNull null],
                                                      }];
                                             }];
    _listeners[handle] = listener;
    result(handle);
  } else if ([@"Query#getDocuments" isEqualToString:call.method]) {
    FIRQuery *query;
    FIRFirestoreSource source = getSource(call.arguments);
    @try {
      query = getQuery(call.arguments);
    } @catch (NSException *exception) {
      result([FlutterError errorWithCode:@"invalid_query"
                                 message:[exception name]
                                 details:[exception reason]]);
    }

    [query
        getDocumentsWithSource:source
                    completion:^(FIRQuerySnapshot *_Nullable snapshot, NSError *_Nullable error) {
                      if (snapshot == nil) {
                        result(getFlutterError(error));
                        return;
                      }
                      result(parseQuerySnapshot(snapshot));
                    }];
  } else if ([@"removeListener" isEqualToString:call.method]) {
    NSNumber *handle = call.arguments[@"handle"];
    [[_listeners objectForKey:handle] remove];
    [_listeners removeObjectForKey:handle];
    result(nil);
  } else if ([@"WriteBatch#create" isEqualToString:call.method]) {
    __block NSNumber *handle = [NSNumber numberWithInt:_nextBatchHandle++];
    FIRWriteBatch *batch = [getFirestore(call.arguments) batch];
    _batches[handle] = batch;
    result(handle);
  } else if ([@"WriteBatch#setData" isEqualToString:call.method]) {
    NSNumber *handle = call.arguments[@"handle"];
    NSDictionary *options = call.arguments[@"options"];
    FIRDocumentReference *document = getDocumentReference(call.arguments);
    FIRWriteBatch *batch = [_batches objectForKey:handle];
    if (![options isEqual:[NSNull null]] &&
        [options[@"merge"] isEqual:[NSNumber numberWithBool:YES]]) {
      [batch setData:call.arguments[@"data"] forDocument:document merge:YES];
    } else {
      [batch setData:call.arguments[@"data"] forDocument:document];
    }
    result(nil);
  } else if ([@"WriteBatch#updateData" isEqualToString:call.method]) {
    NSNumber *handle = call.arguments[@"handle"];
    FIRDocumentReference *document = getDocumentReference(call.arguments);
    FIRWriteBatch *batch = [_batches objectForKey:handle];
    [batch updateData:call.arguments[@"data"] forDocument:document];
    result(nil);
  } else if ([@"WriteBatch#delete" isEqualToString:call.method]) {
    NSNumber *handle = call.arguments[@"handle"];
    FIRDocumentReference *document = getDocumentReference(call.arguments);
    FIRWriteBatch *batch = [_batches objectForKey:handle];
    [batch deleteDocument:document];
    result(nil);
  } else if ([@"WriteBatch#commit" isEqualToString:call.method]) {
    NSNumber *handle = call.arguments[@"handle"];
    FIRWriteBatch *batch = [_batches objectForKey:handle];
    [batch commitWithCompletion:defaultCompletionBlock];
    [_batches removeObjectForKey:handle];
  } else if ([@"Firestore#enablePersistence" isEqualToString:call.method]) {
    bool enable = (bool)call.arguments[@"enable"];
    FIRFirestoreSettings *settings = [[FIRFirestoreSettings alloc] init];
    settings.persistenceEnabled = enable;
    FIRFirestore *db = getFirestore(call.arguments);
    db.settings = settings;
    result(nil);
  } else if ([@"Firestore#settings" isEqualToString:call.method]) {
    FIRFirestoreSettings *settings = [[FIRFirestoreSettings alloc] init];
    if (![call.arguments[@"persistenceEnabled"] isEqual:[NSNull null]]) {
        settings.persistenceEnabled = [call.arguments[@"persistenceEnabled"] boolValue];
    }
    if (![call.arguments[@"host"] isEqual:[NSNull null]]) {
      settings.host = (NSString *)call.arguments[@"host"];
    }
    if (![call.arguments[@"sslEnabled"] isEqual:[NSNull null]]) {
        settings.sslEnabled = [call.arguments[@"sslEnabled"] boolValue];
    }
    if (![call.arguments[@"timestampsInSnapshotsEnabled"] isEqual:[NSNull null]]) {
        settings.timestampsInSnapshotsEnabled = [call.arguments[@"timestampsInSnapshotsEnabled"] boolValue];
    }
    if (![call.arguments[@"cacheSizeBytes"] isEqual:[NSNull null]]) {
      settings.cacheSizeBytes = ((NSNumber *)call.arguments[@"cacheSizeBytes"]).intValue;
    }
    FIRFirestore *db = getFirestore(call.arguments);
    db.settings = settings;
    result(nil);
  } else {
    result(FlutterMethodNotImplemented);
  }
}

@end
