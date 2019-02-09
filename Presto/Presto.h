//  The MIT License (MIT)
//
//  Copyright © 2018 Logan Murray
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
//  o(")_(")
//   PRESTO!
//  
//  An Objective-C REST Framework
//  Designed and implemented by Logan Murray
//  
//  https://github.com/devios1/presto

#import <Foundation/Foundation.h>

@class Presto;
@class PrestoCallbackRecord;
@class PrestoSource;
@class PrestoMetadata;

typedef void (^PrestoCallback)(NSObject *result);
// we should consider adding PrestoFailureCallback which also passes an NSError *error
typedef void (^PrestoRequestTransformer)(NSMutableURLRequest *request); // rename Transformation?
typedef id (^PrestoResponseTransformer)(id response); // sent the decoded JSON object (NSArray* or NSDictionary*)

// these are empty protocols that allow us to attribute properties with meta information
// note that protocols can only be attached to object types, so you should declare your property as NSNumber if you need to attach a protocol to a numerical or boolean type.
@protocol Identifying; // TODO: this will eventually be used to more efficiently equate objects when an array is loaded; for now only isEqual: is supported
@protocol SortKey; // TODO: use this to know what property to sort mutable arrays on (optional)
@protocol DoNotSerialize; // maybe rename to Secure (or add a Secure that will never be serialized)
// should we add a Serialize property as well to act as a whitelist?

@protocol PrestoDelegate

@optional
- (void)objectWillLoad:(id)jsonObject;
- (void)objectDidLoad;

- (void)connectionDropped;
- (void)connectionEstablished;
- (void)authenticationFailed;		// this is meant to alert the app globally that an authentication has failed, not actually handle the failure

- (NSURL *)identifyingURL;
- (id<NSCopying>)identifyingKey; // override to provide a unique identifier for an instance (enables singleton in-place loading)
//- (NSString *)identifyingTemplate; // return something like "http://.../%@"
- (NSArray *)serializingKeys; // serializableProperties

@end

/**
	The Presto class represents a common access point for most global operations within the framework. For example, the `objectOfClass:`, `arrayOfClass:`, `getFromURL:`, etc. methods are replicated as class methods upon this class and provide an alternate means to instantiate objects than creating them directly.
	
	It also provides the general interface for customizing global transformers and mappings of fields to properties.
*/
@interface Presto : NSObject // we should rename/split-off PrestoContext

@property (weak, nonatomic) NSObject<PrestoDelegate> *delegate;
@property (strong, nonatomic) NSMutableDictionary *classIndex; // 2D index of instances by class
@property (strong, nonatomic) Class defaultErrorClass;
@property (nonatomic) NSInteger activeRequests;
@property (nonatomic) BOOL trackParentObjects; // default YES
@property (nonatomic) BOOL showActivityIndicator; // default YES
@property (nonatomic) BOOL overwriteNulls; // default NO -- when NO, in-place loading skips over null-valued fields instead of replacing the existing value

+ (Presto *)defaultInstance;
+ (Class)defaultErrorClass;

/**
	Provides an alternate means of instantiating a class.
	
	This is effectively equivalent to just instantiating the class normally except that the PrestoMetadata instance is also created immediately at this time. It is included mainly for syntactic symmetry.
*/
//+ (id)objectOfClass:(Class)class; **deprecated**

/**
	Instantiates an empty typed `NSMutableArray` instance. Similar to simply instantiating an `NSMutableArray` directly, except that the array knows what class of object it contains. This is important for arrays that are to be loaded remotely from a subsequent Presto call.
*/
//+ (id)arrayOfClass:(Class)class; **deprecated**

// these are duplicated here for convenience and apply to [Presto defaultInstance]
+ (void)globallyMapRemoteField:(NSString *)field toLocalProperty:(NSString *)property;
+ (void)addGlobalRequestTransformer:(PrestoRequestTransformer)transformer;
+ (void)addGlobalResponseTransformer:(PrestoResponseTransformer)transformer;
+ (void)setDefaultErrorClass:(Class)defaultErrorClass;

+ (void)mapRemoteField:(NSString *)field toLocalProperty:(NSString *)property forClass:(Class)class;
//+ (void)addRequestTransformer:(PrestoRequestTransformer)transformer forClass:(Class)class;
//+ (void)addResponseTransformer:(PrestoResponseTransformer)transformer forClass:(Class)class;

+ (void)addSerializationKey:(NSString *)key forClass:(Class)class;
+ (void)addSerializationKeys:(NSArray *)keys forClass:(Class)class;

/**
	Register an instance as a singleton. If there is already an existing instance registered, the new instance will replace it as the designated instance.
*/
+ (void)registerInstance:(id)instance;

+ (PrestoMetadata *)getFromURL:(NSURL *)url;
+ (PrestoMetadata *)putToURL:(NSURL *)url;			// will PUT with no body
+ (PrestoMetadata *)postToURL:(NSURL *)url;			// will POST with no body
+ (PrestoMetadata *)deleteFromURL:(NSURL *)url;

// --

- (id)instantiateClass:(Class)class withDictionary:(NSDictionary *)dict;
- (void)registerInstance:(id)instance;

- (void)globallyMapRemoteField:(NSString *)field toLocalProperty:(NSString *)property;
- (void)addGlobalRequestTransformer:(PrestoRequestTransformer)transformer;
- (void)addGlobalResponseTransformer:(PrestoResponseTransformer)transformer;

// i had originally designed configurations to happen at a class level, but have since moved to favor source-based configuration as it is simpler and more capable
// this legacy class-based configuration will probably change in the future
- (void)mapRemoteField:(NSString *)field toLocalProperty:(NSString *)property forClass:(Class)class;

// TODO: we need to support both white- and black-listing
- (void)addSerializationKey:(NSString *)key forClass:(Class)class;
- (void)addSerializationKeys:(NSArray *)keys forClass:(Class)class;

// --

- (NSString *)propertyNameForField:(NSString *)fieldName forClass:(Class)class;
- (NSString *)fieldNameForProperty:(NSString *)propertyName forClass:(Class)class;
//- (void)transformRequest:(NSMutableURLRequest *)request;
//- (id)transformResponse:(id)jsonObject;
- (BOOL)shouldPropertyBeSerialized:(NSString *)propertyName forClass:(Class)class;

@end

@interface PrestoCallbackRecord : NSObject

//@property (weak, nonatomic) id target;
//@property (strong, nonatomic) id strongTarget;		// we can also use this to tell if the object is a completion because a callback is a completion iff it has a strong target
@property (strong, nonatomic) NSDate* timestamp; // not used yet, but might be a good idea
@property (strong, nonatomic) PrestoCallback success;
@property (strong, nonatomic) PrestoCallback failure; // note: if a failure block is not provided, the success block is called regardless of outcome (success/failure)

//- (id)target;
//- (void)setTarget:(id)target;
//- (BOOL)isCompletion;

@end

@interface PrestoCompletionRecord : PrestoCallbackRecord

@property (strong, nonatomic) id target;

@end

@interface PrestoDependencyRecord : PrestoCallbackRecord

@property (weak, nonatomic) id owner;
@property (nonatomic) BOOL hasOwner;

@end

@interface PrestoSource : NSObject

@property (weak, nonatomic) PrestoMetadata* target;			// the parent meta object (rename parent?)
@property (strong, nonatomic) NSURL* url;
@property (nonatomic) BOOL isLoading;
@property (nonatomic) BOOL isLoaded;
@property (readonly, nonatomic) BOOL isCompleted;
@property (readonly, nonatomic) NSDate* loadedTime;			// there is a valid definition available
@property (readonly, nonatomic) NSDate* loadingTime;		// we are waiting on a response from the server
@property (strong, nonatomic) NSMutableURLRequest* request;	// the request representing the latest reload
//@property (strong, nonatomic) NSURLConnection* connection;
@property (strong, nonatomic) NSString* method;				// the last HTTP method used to load this object
@property (strong, nonatomic) NSObject *payload;			// outgoing payload reference
@property (strong, nonatomic) NSData *payloadData;			// outgoing payload data
@property (strong, nonatomic) NSData *lastPayload;			// last incoming payload
@property (strong, nonatomic) id serializationTemplate;		// template for serializing the payload
@property (nonatomic) NSInteger statusCode;					// the last HTTP status code
@property (strong, nonatomic) NSError* error;				// we received an error from the last request
@property (strong, nonatomic) id errorResponse;		// can probably improve this name
@property (nonatomic) NSTimeInterval refreshInterval;
//@property (strong, nonatomic) NSMutableArray* serializationKeys; // this is a temp hack to get around knowing what properties to serialize; this will be improved!
@property (nonatomic) BOOL active; // allows a source to be turned on/off

// experimental:
//@property (strong, nonatomic) Class nativeClass;	// the native class to use at the given depth in a successful response
//@property (nonatomic) int classDepth;							// the depth of the tree at which targetClass takes over from NSArray/NSDictionary
//@property (strong, nonatomic) Class errorClass;		// the class of object to instantiate as the response if the request fails (returns non-200)
//@property (nonatomic) int errorDepth;

@property (strong, nonatomic) NSMutableArray *requestTransformers;
@property (strong, nonatomic) NSMutableArray *responseTransformers;

+ (instancetype)sourceWithURL:(NSURL *)url method:(NSString *)method payload:(id)payload;

@end

// TODO: since this by and large the main class in Presto perhaps we should rename this class to Presto and rename the Presto class to something like PrestoManager or PrestoContext
// of course we'd want to move the global class methods down here to keep the syntax the same.
@interface PrestoMetadata : NSObject

// TODO: we may actually want to support multiple targets to allow the same metadata to be shared by several objects (for example if two metadatas are merged)
@property (readonly, nonatomic) id target;			// the object that this metadata applies to (rename host?)
@property (weak, nonatomic) NSObject *parent; // a weak reference to the object that contains this object
//@property (strong, nonatomic) Class targetClass;	// the class of the target/host **deprecated**
@property (strong, nonatomic) Class nativeClass;	// the native class to use at the given depth in a successful response
@property (nonatomic) int classDepth;							// the depth of the tree at which targetClass takes over from NSArray/NSDictionary
@property (strong, nonatomic) Class errorClass;		// the class of object to instantiate as the response if the request fails (returns non-200)
@property (nonatomic) int errorDepth;

@property (strong, nonatomic) Presto *manager;		// the manager this object should use (rename context?)
// TODO: i think we should deprecate multiple sources for simplicity and reverse updating etc.
//@property (readonly, nonatomic) NSMutableSet *sources;			// keyed on propertyName or NSNull
@property (strong, nonatomic) PrestoSource *source; // temp--we should move those props back in here
@property (nonatomic) BOOL isDeferred;
@property (readonly, nonatomic) BOOL isLoading;
@property (readonly, nonatomic) BOOL isLoaded;
@property (readonly, nonatomic) BOOL isCompleted;	// all of the object's sources are either loaded or errored
//@property (readonly, nonatomic) BOOL isSuccessful;	// true if the server returned 200 and the object was successfully loaded
@property (readonly, nonatomic) NSError *error;					// we received an error from the last request
@property (readonly, nonatomic) id errorResponse;		// the (possibly classed) response object from the last request
@property (readonly, nonatomic) NSInteger statusCode;
//@property (strong, nonatomic) NSDate* lastUpdate;
//@property (strong, nonatomic) NSMutableArray* completions;
//@property (strong, nonatomic) NSMutableArray* dependencies;
@property (strong, nonatomic) NSMutableArray* callbacks;
@property (nonatomic) NSTimeInterval refreshInterval;
@property (readonly, nonatomic) NSString *lastResponseString;
@property (readonly, nonatomic) id lastResponseObject;

// array-related properties (these only apply if target is NSMutableArray)
//@property (strong, nonatomic) Class arrayClass;		// the class of elements if target is a mutable array **deprecated**
@property (nonatomic) BOOL append; // only applies to arrays; when YES, new elements are appended to the target array and existing elements are not removed (TODO: this should probably also apply to dictionaries)
@property (strong, nonatomic) NSString *sortKey; // experimental--automatically sort an array based on some key (it would be nice if this could also be set up with a protocol)

- (PrestoMetadata *)reload; // replace with getSelf?
- (PrestoMetadata *)reload:(BOOL)force;
- (PrestoMetadata *)reloadIfOlderThan:(NSTimeInterval)age;
// i wonder if the completions should have parameters, such as the target object?
- (PrestoMetadata *)reloadWithCompletion:(PrestoCallback)completion;
- (PrestoMetadata *)reloadWithCompletion:(PrestoCallback)success failure:(PrestoCallback)failure; // todo
//- (void)loadWithCompletion:(PrestoCallback)completion force:(BOOL)force;

/**
	Experimental. The idea here is you can call `loadWithObject` on an existing instance to load it in place with the result of some other remote source such as a PUT or POST, rather than replacing it with a new instance.
*/
- (PrestoMetadata *)loadWithObject:(NSObject *)object;
- (PrestoMetadata *)appendFrom:(NSObject *)source;

/**
	Tells an object not to load itself automatically, even if completions or dependencies are attached. You must explicitly call `reload` when you are ready for the object to be loaded.
*/
- (PrestoMetadata *)deferLoad;
- (PrestoMetadata *)invalidate;
- (PrestoMetadata *)signalChange; // experimental--calls dependency blocks manually

// note that calling these does not immediately load the object (that happens when you add a completion or dependency)

/**
	Sets the source of the receiving object to the provided URL.
	
	Note: The remote source is not loaded immediately upon calling this method, unless it already has completions and/or dependencies. Loading generally takes place upon the first completion or dependency attached to the object. If you wish to force the object to load immediately (for example to pre-fetch information that will be needed in the future), call `reload` after calling this method.
*/
- (PrestoMetadata *)getFromURL:(NSURL *)url;
/**
	Creates a new metadata object that represents the response of a PUT request to the provided URL using the receiving object as the body of the request.
	
	You should type the response by calling either `objectOfClass:` or `arrayOfClass:` upon the returned object.
*/
- (PrestoMetadata *)putToURL:(NSURL *)url;
/**
	Creates a new metadata object that represents the response of a POST request to the provided URL using the receiving object as the body of the request.
	
	You should type the response by calling either `objectOfClass:` or `arrayOfClass:` upon the returned object.
*/
- (PrestoMetadata *)postToURL:(NSURL *)url;
/**
	Creates a new metadata object that represents the response of a DELETE request to the provided URL using the receiving object as the body of the request. If you do not need a body in the DELETE request, instead call the `deleteFromURL:` class method of `Presto`.
	
	You should type the response by calling either `objectOfClass:` or `arrayOfClass:` upon the returned object.
*/
- (PrestoMetadata *)deleteFromURL:(NSURL *)url;

/**
	Equivalent to `reload`. Exists for syntactic symmetry.
*/
- (PrestoMetadata *)getSelf;
- (PrestoMetadata *)putSelf; // TODO: verify that calling this on a class that implements an identifyingKey returns the current object if the response includes its id (i.e. in-place load)
- (PrestoMetadata *)postSelf;
- (PrestoMetadata *)deleteSelf;
//- (void)putAndLoad; // assumes the response of the PUT is the current state of the object
//- (void)postAndLoadSelf; // you really shouldn't need to use this one if your API is properly implemented; POST should always create a new object, so it doesn't make sense to reload an existing object with its result

//- (void)loadFromSource:(PrestoSource *)source force:(BOOL)force;
- (BOOL)loadWithJSONString:(NSString *)json;
- (BOOL)loadWithJSONObject:(id)jsonObject;
- (BOOL)loadWithDictionary:(NSDictionary *)dictionary;
- (BOOL)loadWithArray:(NSArray *)array;

//- (id)objectOfClass:(Class)class; **deprecated**
//- (id)arrayOfClass:(Class)class; **deprecated** // this is id to avoid type warnings
- (PrestoMetadata *)withClass:(Class)class atDepth:(int)depth;
- (PrestoMetadata *)withErrorClass:(Class)class atDepth:(int)depth; // NOTE: depth is not supported on this call yet

- (NSString *)toJSONString;
- (NSString *)toJSONStringWithTemplate:(id)template;
//- (NSString *)toJSONString:(BOOL)pretty;
- (id)toJSONObject;
- (NSDictionary *)toDictionary;
- (NSDictionary *)toDictionaryWithTemplate:(id)template;
//- (NSDictionary *)toDictionaryComplete:(BOOL)complete; // had to add this temporarily until serialization is better

- (PrestoMetadata *)withUsername:(NSString *)username password:(NSString *)password; // not implemented

- (PrestoMetadata *)withRequestTransformer:(PrestoRequestTransformer)transformer;
- (PrestoMetadata *)withResponseTransformer:(PrestoResponseTransformer)transformer;

/**
	This is a handy function that accepts a sample JSON payload and uses it as a template to construct a corresponding payload with the same fields and data from the current instance.
	
	Only the keys are used; the values and their types are ignored.
*/
- (PrestoMetadata *)withTemplate:(NSString *)jsonTemplate;

// Note: The difference between reloadWithCompletion: and onComplete: is that while onComplete: will make sure the object is loaded once, reloadWithCompletion: performs a soft reload every time it is called.

// it's important to note that completions will always be called, whereas dependencies keep weak references and will only be called if their target is still alive

- (PrestoMetadata *)onComplete:(PrestoCallback)completion;
- (PrestoMetadata *)onComplete:(PrestoCallback)success failure:(PrestoCallback)failure;

// TODO: consider changing "withTarget" to "withViewController" since that's really its intended purpose
- (PrestoMetadata *)onChange:(PrestoCallback)dependency;
- (PrestoMetadata *)onChange:(PrestoCallback)dependency withTarget:(id)target;

- (PrestoMetadata *)clearDependencies; // TODO: we need a better way to identify dependencies so individual ones can be removed
// i actually wonder if we should use a target/selector pattern instead…

- (void)uninstall; // uninstalls the current metadata object from its host

@end

@interface NSObject (PrestoMetadata)

// Presto makes this one property available to *all* NSObjects, on demand
@property (readonly, nonatomic) PrestoMetadata *presto;

@end
