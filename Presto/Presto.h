//  The MIT License (MIT)
//
//  Copyright © 2015 Vivonet
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.

//    ( Y )
//   (  . .)
//  o(") (")
//   PRESTO!
//  
//  An Objective-C REST Framework
//  Designed and coded by Logan Murray

#import <Foundation/Foundation.h>

@class Presto;
@class PrestoCallbackRecord;
@class PrestoSource;
@class PrestoMetadata;

typedef void (^PrestoCallback)( NSObject *result );
typedef void (^PrestoRequestTransformer)( NSMutableURLRequest *request );
typedef id (^PrestoResponseTransformer)( id response ); // sent the decoded JSON object (NSArray* or NSDictionary*)

// these are empty protocols that allow us to attribute properties with meta information
// note that protocols can only be attached to object types, so you should declare your property as NSNumber if you need to attach a protocol to a numerical or boolean type.
@protocol Identifying; // TODO: this will eventually be used to more efficiently equate objects when an array is loaded; for now only isEqual: is supported
@protocol DoNotSerialize;

@protocol PrestoDelegate

@optional
- (void)objectWillLoad:(id)jsonObject;
- (void)objectDidLoad;

- (void)connectionDropped;
- (void)connectionEstablished;
- (void)authenticationFailed;		// this is meant to alert the app globally that an authentication has failed, not actually handle the failure

@end

@interface Presto : NSObject

@property (weak, nonatomic) NSObject<PrestoDelegate> *delegate;

+ (Presto *)defaultInstance;

+ (id)objectOfClass:(Class)class;
+ (id)arrayOfClass:(Class)class;

// these are duplicated here for convenience and apply to [Presto defaultInstance]
+ (void)globallyMapRemoteField:(NSString *)field toLocalProperty:(NSString *)property;
+ (void)addGlobalRequestTransformer:(PrestoRequestTransformer)transformer;
+ (void)addGlobalResponseTransformer:(PrestoResponseTransformer)transformer;

+ (void)mapRemoteField:(NSString *)field toLocalProperty:(NSString *)property forClass:(Class)class;
//+ (void)addRequestTransformer:(PrestoRequestTransformer)transformer forClass:(Class)class;
//+ (void)addResponseTransformer:(PrestoResponseTransformer)transformer forClass:(Class)class;

+ (void)addSerializationKey:(NSString *)key forClass:(Class)class;
+ (void)addSerializationKeys:(NSArray *)keys forClass:(Class)class;

+ (PrestoMetadata *)getFromURL:(NSURL *)url;
+ (PrestoMetadata *)deleteFromURL:(NSURL *)url;

// --

- (void)globallyMapRemoteField:(NSString *)field toLocalProperty:(NSString *)property;
- (void)addGlobalRequestTransformer:(PrestoRequestTransformer)transformer;
- (void)addGlobalResponseTransformer:(PrestoResponseTransformer)transformer;

- (void)mapRemoteField:(NSString *)field toLocalProperty:(NSString *)property forClass:(Class)class;
//- (void)addRequestTransformer:(PrestoRequestTransformer)transformer forClass:(Class)class;
//- (void)addResponseTransformer:(PrestoResponseTransformer)transformer forClass:(Class)class;

// TODO: we need to support both white- and black-listing
- (void)addSerializationKey:(NSString *)key forClass:(Class)class;
- (void)addSerializationKeys:(NSArray *)keys forClass:(Class)class;

// --

- (NSString *)propertyNameForField:(NSString *)fieldName forClass:(Class)class;
- (NSString *)fieldNameForProperty:(NSString *)propertyName forClass:(Class)class;
- (void)transformRequest:(NSMutableURLRequest *)request;
- (id)transformResponse:(id)jsonObject;
- (BOOL)shouldPropertyBeSerialized:(NSString *)propertyName forClass:(Class)class;

@end

@interface PrestoCallbackRecord : NSObject

@property (strong, nonatomic) id strongTarget;		// for completions
@property (weak, nonatomic) id weakTarget;			// for dependencies
@property (strong, nonatomic) NSDate* timestamp; // not used yet, but might be a good idea
@property (strong, nonatomic) PrestoCallback success;
@property (strong, nonatomic) PrestoCallback failure; // note: if a failure block is not provided, the success block is called regardless of outcome (success/failure)
@property (nonatomic) BOOL hasTarget;

@end

@interface PrestoSource : NSObject

@property (weak, nonatomic) PrestoMetadata* target;				// the parent meta object (rename parent?)
@property (strong, nonatomic) NSURL* url;
@property (nonatomic) BOOL isLoading;
@property (nonatomic) BOOL isLoaded;
@property (readonly, nonatomic) BOOL isCompleted;
@property (readonly, nonatomic) NSDate* loadedTime;				// there is a valid definition available
@property (readonly, nonatomic) NSDate* loadingTime;			// we are waiting on a response from the server
@property (strong, nonatomic) NSMutableURLRequest* request;		// the request representing the latest reload
@property (strong, nonatomic) NSURLConnection* connection;
@property (strong, nonatomic) NSString* method;				// the last HTTP method used to load this object
@property (strong, nonatomic) NSObject *payload;			// outgoing payload reference
@property (strong, nonatomic) NSData *payloadData;			// outgoing payload data
@property (strong, nonatomic) NSData *lastPayload;			// last incoming payload
@property (nonatomic) NSInteger statusCode;						// the last HTTP status code
@property (strong, nonatomic) NSError* error;					// we received an error from the last request
@property (nonatomic) NSTimeInterval refreshInterval;
@property (strong, nonatomic) NSMutableArray* serializationKeys; // this is a temp hack to get around knowing what properties to serialize; this will be improved!
@property (nonatomic) BOOL active; // allows a source to be turned on/off

@property (strong, nonatomic) NSMutableArray *requestTransformers;
@property (strong, nonatomic) NSMutableArray *responseTransformers;

+ (instancetype)sourceWithURL:(NSURL *)url method:(NSString *)method payload:(id)payload;

//- (PrestoSource *)withPayloadData:(NSData *)payloadData;
//- (PrestoSource *)withPayloadString:(NSString *)payloadString;
//- (PrestoSource *)withRequestTransformer:(PrestoRequestTransformer)transformer;
//- (PrestoSource *)withResponseTransformer:(PrestoResponseTransformer)transformer;

@end

@interface PrestoMetadata : NSObject

@property (readonly, nonatomic) id target;			// the object that this metadata applies to
//@property (strong, nonatomic) id strongTarget;		// a strong version of the target for those cases where a metadata instantiates its own target (so far we haven't actually needed this)
@property (strong, nonatomic) Class targetClass;
@property (strong, nonatomic) Class arrayClass;				// the class of elements (if target is a mutable array)
@property (strong, nonatomic) Presto *manager;		// the manager this object should use
// TODO: i think we should deprecate multiple sources for simplicity and reverse updating etc.
//@property (readonly, nonatomic) NSMutableSet *sources;			// keyed on propertyName or NSNull
@property (strong, nonatomic) PrestoSource *source; // temp--we should move those props back in here
@property (readonly, nonatomic) BOOL isLoading;
@property (readonly, nonatomic) BOOL isLoaded;
@property (readonly, nonatomic) BOOL isCompleted;	// all of the object's sources are either loaded or errored
//@property (readonly, nonatomic) BOOL isSuccessful;	// true if the server returned 200 and the object was successfully loaded
@property (readonly, nonatomic) NSError* error;					// we received an error from the last request
@property (readonly, nonatomic) NSInteger statusCode;
//@property (strong, nonatomic) NSDate* lastUpdate;
@property (readonly, nonatomic) NSMutableArray* callbacks;
@property (readonly, nonatomic) NSMutableArray* dependencies;
@property (nonatomic) NSTimeInterval refreshInterval;

- (void)load; // replace with getSelf?
- (void)load:(BOOL)force;
- (void)loadIfOlderThan:(NSTimeInterval)age; // TODO: implement this!
// i wonder if the completions should have parameters, such as the target object?
- (void)loadWithCompletion:(PrestoCallback)completion;
- (void)loadWithCompletion:(PrestoCallback)success failure:(PrestoCallback)failure; // todo
//- (void)loadWithCompletion:(PrestoCallback)completion force:(BOOL)force;

// note that calling these does not immediately load the object (that happens when you add a completion or dependency)
- (PrestoMetadata *)getFromURL:(NSURL *)url;
- (PrestoMetadata *)putToURL:(NSURL *)url;
- (PrestoMetadata *)postToURL:(NSURL *)url;
- (PrestoMetadata *)deleteFromURL:(NSURL *)url;

- (PrestoMetadata *)getSelf;
- (PrestoMetadata *)putSelf;
- (PrestoMetadata *)postSelf;
- (PrestoMetadata *)deleteSelf;
//- (void)putAndLoadSelf;
//- (void)postAndLoadSelf; // you really shouldn't need to use this one if your API is properly implemented; POST should always create a new object, so it doesn't make sense to reload an existing object with its result

- (void)loadFromSource:(PrestoSource *)source force:(BOOL)force;
- (void)loadWithJSONString:(NSString *)json;
- (void)loadWithJSONObject:(id)jsonObject;
- (void)loadWithDictionary:(NSDictionary *)dictionary;
- (void)loadWithArray:(NSArray *)array;

- (id)objectOfClass:(Class)class;
- (id)arrayOfClass:(Class)class; // this is id to avoid type warnings

- (NSString *)toJSONString:(BOOL)pretty;
- (id)toJSONObject;

- (PrestoMetadata *)withUsername:(NSString *)username password:(NSString *)password;

- (PrestoMetadata *)withRequestTransformer:(PrestoRequestTransformer)transformer;
- (PrestoMetadata *)withResponseTransformer:(PrestoResponseTransformer)transformer;

// Note: The difference between loadWithCompletion: and onComplete: is that while onComplete: will make sure the object is loaded once, loadWithCompletion: performs a soft reload every time it is called.

// it's important to note that completions will always be called, whereas dependencies keep weak references and will only be called if their target is still alive

- (PrestoMetadata *)onComplete:(PrestoCallback)completion;
- (PrestoMetadata *)onComplete:(PrestoCallback)success failure:(PrestoCallback)failure;

- (PrestoMetadata *)onChange:(PrestoCallback)dependency;
- (PrestoMetadata *)onChange:(PrestoCallback)dependency withTarget:(id)target;

- (void)uninstall; // uninstalls the current metadata object from its host

@end

@interface NSObject (PrestoMetadata)

// Presto makes this one property available to *all* NSObjects, on demand
@property (readonly, nonatomic) PrestoMetadata *presto;

@end
