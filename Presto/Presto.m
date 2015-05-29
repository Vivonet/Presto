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
//  o(")_(")
//   PRESTO!
//  
//  An Objective-C REST Framework
//  Designed and coded by Logan Murray

//  I apologize for the current state of this file. There is a lot of commented out crap left over from previous design iterations. It will definitely be cleaned up.

#import <objc/runtime.h>
#import <UIKit/UIKit.h>
#import "Presto.h"
#import "Reachability.h"

static const BOOL LOG_PAYLOADS = YES;
static const BOOL LOG_WARNINGS = YES;
static const BOOL LOG_ERRORS = YES;
static const BOOL LOG_VERBOSE = YES;
static const BOOL LOG_ZOMBIES = YES;

static Presto *_defaultInstance;
static id ValueForUndefinedKey;

#define PRLog(FORMAT, ...) printf("%s\n", [[NSString stringWithFormat:FORMAT, ##__VA_ARGS__] UTF8String]);

#pragma mark - Presto

@interface Presto ()

// these are two-dimensional dictionaries first indexed on Class
@property (strong, nonatomic) NSMutableDictionary *fieldToPropertyMappings;
@property (strong, nonatomic) NSMutableDictionary *propertyToFieldMappings;
@property (strong, nonatomic) NSMutableArray *requestTransformers;
@property (strong, nonatomic) NSMutableArray *responseTransformers;
@property (strong, nonatomic) NSMutableDictionary *serializationKeys; // dictionary of NSMutableSets
@property (strong, nonatomic) NSMutableDictionary *warnedKeys;
@property (nonatomic) BOOL connectionDropped;

@end

@implementation Presto

+ (void)initialize {
	ValueForUndefinedKey = [NSObject new]; // an empty object
}

+ (Presto *)defaultInstance {
	if ( _defaultInstance == nil ) {
		_defaultInstance = [Presto new];
	}
	
	return _defaultInstance;
}

// this method actually amounts to little more than simply instantiating the object yourself, it's really only here for symmetry...
+ (id)objectOfClass:(Class)class {
	return [[PrestoMetadata new] objectOfClass:class];
}

+ (id)arrayOfClass:(Class)class {
	return [[PrestoMetadata new] arrayOfClass:class];
}

// the following are convenience proxies to [Presto defaultInstance]
+ (void)globallyMapRemoteField:(NSString *)field toLocalProperty:(NSString *)property {
	[[Presto defaultInstance] globallyMapRemoteField:field toLocalProperty:property];
}

+ (void)addGlobalRequestTransformer:(PrestoRequestTransformer)transformer {
	[[Presto defaultInstance] addGlobalRequestTransformer:transformer];
}

+ (void)addGlobalResponseTransformer:(PrestoResponseTransformer)transformer {
	[[Presto defaultInstance] addGlobalResponseTransformer:transformer];
}

+ (void)mapRemoteField:(NSString *)field toLocalProperty:(NSString *)property forClass:(Class)class {
	[[Presto defaultInstance] mapRemoteField:field toLocalProperty:property forClass:class];
}

+ (void)addSerializationKey:(NSString *)key forClass:(Class)class {
	[[Presto defaultInstance] addSerializationKey:key forClass:class];
}

+ (void)addSerializationKeys:(NSArray *)keys forClass:(Class)class {
	[[Presto defaultInstance] addSerializationKeys:keys forClass:class];
}

#pragma mark -

+ (PrestoMetadata *)getFromURL:(NSURL *)url {
	PrestoMetadata *result = [PrestoMetadata new];
	result.source = [PrestoSource new];
	result.source.url = url;
	result.source.method = @"GET";
	return result;
}

+ (PrestoMetadata *)deleteFromURL:(NSURL *)url {
	PrestoMetadata *result = [PrestoMetadata new];
	result.source = [PrestoSource new];
	result.source.url = url;
	result.source.method = @"DELETE";
	return result;
}

// putToURL and postToURL don't make sense in a global context because they need an instance to represent the payload

#pragma mark -

- (instancetype)init {
	self = [super init];
	if ( self ) {
		self.fieldToPropertyMappings = [NSMutableDictionary new];
		self.propertyToFieldMappings = [NSMutableDictionary new];
		self.requestTransformers = [NSMutableArray new];
		self.responseTransformers = [NSMutableArray new];
		self.serializationKeys = [NSMutableDictionary new];
		self.warnedKeys = [NSMutableDictionary new];
		
		self.showActivityIndicator = YES;
	}
	return self;
}

#pragma mark -

// TODO: we might want to lock this, but it's currently only called on the main thread anyway
- (void)setActiveRequests:(NSInteger)activeRequests {
	_activeRequests = activeRequests;
	
	if ( self.showActivityIndicator )
		[UIApplication sharedApplication].networkActivityIndicatorVisible = self.activeRequests > 0;
}

#pragma mark -

- (void)globallyMapRemoteField:(NSString *)field toLocalProperty:(NSString *)property {
	[self mapRemoteField:field toLocalProperty:property forClass:[NSObject class]];
}

// now that these are like this should we bother with the method or just expose the array again?
- (void)addGlobalRequestTransformer:(PrestoRequestTransformer)transformer {
//	[self addRequestTransformer:transformer forClass:[NSObject class]];
	[self.requestTransformers addObject:transformer];
}

- (void)addResponseTransformer:(PrestoResponseTransformer)transformer {
//	[self addResponseTransformer:transformer forClass:[NSObject class]];
	[self.responseTransformers addObject:transformer];
}

- (void)mapRemoteField:(NSString *)field toLocalProperty:(NSString *)property forClass:(Class)class {
//	id<NSCopying> key = (id<NSCopying>)class ?: [NSNull null];
	
	if ( self.fieldToPropertyMappings[class] == nil ) {
		[(NSMutableDictionary *)_fieldToPropertyMappings setObject:[NSMutableDictionary new] forKey:(id<NSCopying>)class];
	}
	[(NSMutableDictionary *)self.fieldToPropertyMappings[class] setObject:property forKey:field];
	
	if ( self.propertyToFieldMappings[class] == nil ) {
		[(NSMutableDictionary *)_propertyToFieldMappings setObject:[NSMutableDictionary new] forKey:(id<NSCopying>)class];
	}
	[(NSMutableDictionary *)self.propertyToFieldMappings[class] setObject:field forKey:property];
}

//- (void)addRequestTransformer:(PrestoRequestTransformer)transformer forClass:(Class)class {
//	if ( self.requestTransformers[class] == nil ) {
//		[(NSMutableDictionary *)_requestTransformers setObject:[NSMutableArray new] forKey:(id<NSCopying>)class];
//	}
//	[(NSMutableArray *)_requestTransformers[class] addObject:transformer];
//}
//
//- (void)addResponseTransformer:(PrestoResponseTransformer)transformer forClass:(Class)class {
//	if ( self.responseTransformers[class] == nil ) {
//		[(NSMutableDictionary *)_responseTransformers setObject:[NSMutableArray new] forKey:(id<NSCopying>)class];
//	}
//	[(NSMutableArray *)_responseTransformers[class] addObject:transformer];
//}

- (void)addSerializationKey:(NSString *)key forClass:(Class)class {
	if ( self.serializationKeys[class] == nil ) {
		[(NSMutableDictionary *)_serializationKeys setObject:[NSMutableSet new] forKey:(id<NSCopying>)class];
	}
	[(NSMutableSet *)_serializationKeys[class] addObject:key];
}

- (void)addSerializationKeys:(NSArray *)keys forClass:(Class)class {
	for ( NSString *key in keys )
		[self addSerializationKey:key forClass:class];
}

#pragma mark -

- (NSString *)propertyNameForField:(NSString *)fieldName forClass:(Class)class {
	NSString *propertyName;
	while ( class != nil ) {
		NSDictionary *fieldToPropertyMappings = self.fieldToPropertyMappings[class];
		if ( fieldToPropertyMappings && fieldToPropertyMappings[fieldName] != nil )
			propertyName = fieldToPropertyMappings[fieldName];
		// should we break? does it make sense to keep going?
		class = [class superclass];
	}
	return propertyName ?: fieldName;
}

- (NSString *)fieldNameForProperty:(NSString *)propertyName forClass:(Class)class {
	NSString *fieldName;
	while ( class != nil ) {
		NSDictionary *propertyToFieldMappings = self.propertyToFieldMappings[class];
		if ( propertyToFieldMappings && propertyToFieldMappings[propertyName] != nil )
			fieldName = propertyToFieldMappings[propertyName];
		// should we break? does it make sense to keep going?
		class = [class superclass];
	}
	return fieldName ?: propertyName;
}

//- (void)transformRequest:(NSMutableURLRequest *)request {
//
//}
//
//- (id)transformResponse:(id)jsonObject {
//	for ( PrestoResponseTransformer transformer in self.responseTransformers )
//		jsonObject = transformer( jsonObject );
//	
//	return jsonObject;
//}

//- (void)transformRequest:(NSMutableURLRequest *)request forClass:(Class)class {
//	while ( class != nil ) {
//		NSArray *transformers = self.requestTransformers[class];
//		for ( PrestoRequestTransformer transformer in transformers )
//			transformer( request );
//		class = [class superclass];
//	}
//}
//
//- (id)transformResponse:(id)jsonObject forClass:(Class)class {
//	while ( class != nil ) {
//		NSArray *transformers = self.responseTransformers[class];
//		for ( PrestoResponseTransformer transformer in transformers ) {
//			jsonObject = transformer( jsonObject ); // make sure these don't return nil! (maybe safety that? redesign?)
//			NSAssert( jsonObject != nil, @"Transformer neglected to return the dictionary." );
//		}
//		// should we break? does it make sense to keep going?
//		class = [class superclass];
//	}
//	return jsonObject;
//}

- (BOOL)shouldPropertyBeSerialized:(NSString *)propertyName forClass:(Class)class {
	NSArray* ignoreKeys = @[@"superclass", @"hash", @"debugDescription"];
	if ( [ignoreKeys containsObject:propertyName] )
		return NO;
//	if ( [propertyName isEqualToString:@"superclass"]
//		|| [propertyName isEqualToString:@"debugDescription"] ) // never serialize these
//		return NO;
	NSMutableSet *serializationKeys = self.serializationKeys[class];
	if ( !serializationKeys || [serializationKeys containsObject:propertyName] )
		return YES;
	else
		return NO;
}

#pragma mark -

- (void)warnProperty:(NSString *)propertyName forClass:(Class)class valueClass:(Class)valueClass {
	if ( !LOG_WARNINGS )
		return;
	
	if ( self.warnedKeys[class] == nil ) {
		self.warnedKeys[(id<NSCopying>)class] = [NSMutableSet new];
	}
	
	if ( ![self.warnedKeys[class] containsObject:propertyName] ) {
		PRLog(@"Presto WARNING: Property ‘%@’ (%@) not found in class %@.", propertyName, valueClass, class);
		[self.warnedKeys[class] addObject:propertyName];
	}
}

//- (NSString *)stringForJSONType:(Class)jsonClass {
//	if ( jsonClass == 
//}

@end

#pragma mark - PrestoCallbackRecord

@implementation PrestoCallbackRecord

@end

#pragma mark - PrestoSource

@implementation PrestoSource

// this stuff is old; deprecate it; in fact deprecate all of prestosource

//+ (instancetype)sourceWithURL:(NSURL *)url {
//	return [self sourceWithURL:url method:nil payload:nil requestTransformer:nil responseTransformer:nil];
//}

+ (instancetype)sourceWithURL:(NSURL *)url method:(NSString *)method payload:(id)payload {
	PrestoSource *source = [PrestoSource new];
	source.url = url;
	source.method = method ?: @"GET";
	source.payload = payload;
	return source;
}

//+ (instancetype)sourceWithURL:(NSURL *)url requestTransformer:(PrestoRequestTransformer)requestTransformer responseTransformer:(PrestoResponseTransformer)responseTransformer {
//	return [self sourceWithURL:url method:nil payload:nil requestTransformer:requestTransformer responseTransformer:responseTransformer];
//}
//
//+ (instancetype)sourceWithURL:(NSURL *)url method:(NSString *)method payload:(id)payload requestTransformer:(PrestoRequestTransformer)requestTransformer responseTransformer:(PrestoResponseTransformer)responseTransformer {
//	PrestoSource *source = [PrestoSource new];
//	source.url = url;
//	source.method = method;
//	source.payload = payload;
//	if ( requestTransformer )
//		[source.requestTransformers addObject:requestTransformer];
//	if ( responseTransformer )
//		[source.responseTransformers addObject:responseTransformer];
//	return source;
//}
//
//#pragma mark -

- (instancetype)init {
	self = [super init];
	if ( self ) {
		self.serializationKeys = [NSMutableArray new];
		
		// TODO: maybe change these to lazy-load
		self.requestTransformers = [NSMutableArray new];
		self.responseTransformers = [NSMutableArray new];
	}
	return self;
}

- (BOOL)isLoading {
	return self.loadingTime != nil;
}

- (BOOL)isLoaded {
	return self.loadedTime != nil;
}

- (void)setIsLoading:(BOOL)isLoading {
	if ( isLoading ) {
//		NSDate* previousLoading = _loadingTime;
		_loadingTime = [NSDate date];
//		PRLog(@"****** setting isLoading from %f to %f for %@", [previousLoading timeIntervalSinceReferenceDate], [_loadingTime timeIntervalSinceReferenceDate], self);
	} else {
//		PRLog(@"***** setting isLoading to nil for %@", self);
		_loadingTime = nil;
	}
}

- (void)setIsLoaded:(BOOL)isLoaded {
	if ( isLoaded ) {
		_loadedTime = [NSDate date];
		self.error = nil; // does this make sense??
//		if ( [self.target respondsToSelector:@selector(objectLoaded)] )
//			[self.target objectLoaded];
	} else
		_loadedTime = nil;
}

- (BOOL)isCompleted {
	return self.isLoaded || self.error ;//|| self.statusCode != 200;
}

- (void)setError:(NSError *)error {
	_error = error;
	
	if ( error && LOG_ERRORS )
		PRLog(@"ERROR: %d %@\n%@", (int)self.statusCode, self, self.error);
}

- (void)setRefreshInterval:(NSTimeInterval)refreshInterval {
	_refreshInterval = refreshInterval;
	
	if ( _refreshInterval != INFINITY && _refreshInterval != 0 ) { // both 0 and INFINITY mean never
		__block __weak typeof(self) weakSelf = self;
		dispatch_after( dispatch_time(DISPATCH_TIME_NOW, (int64_t)(self.refreshInterval * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
			typeof(weakSelf) strongSelf = weakSelf;
			if ( strongSelf ) {
				[strongSelf.target load]; // verify .target
				strongSelf.refreshInterval = strongSelf.refreshInterval; // queue next refresh
			}
		});
	}
}

#pragma mark -

//- (PrestoSource *)withMethod:(NSString *)method {
//	self.method = method;
//	return self;
//}
//
//- (PrestoSource *)withPayload:(id)payload {
//	self.payload = payload;
//	return self;
//}
//
//- (PrestoSource *)withPayloadData:(NSData *)payloadData {
//	self.payloadData = payloadData;
//	return self;
//}
//
//- (PrestoSource *)withPayloadString:(NSString *)payloadString {
//	self.payloadData = [payloadString dataUsingEncoding:NSUTF8StringEncoding];
//	return self;
//}
//
//- (PrestoSource *)withRequestTransformer:(PrestoRequestTransformer)transformer {
//	[self.requestTransformers addObject:transformer];
//	return self;
//}
//
//- (PrestoSource *)withResponseTransformer:(PrestoResponseTransformer)transformer {
//	[self.responseTransformers addObject:transformer];
//	return self;
//}

//#pragma mark -
//
//- (void)load {
//	[self.target loadFromSource:self force:NO];
//}
//
//- (void)load:(BOOL)force {
//	[self.target loadFromSource:self force:force];
//}
//
//- (void)loadWithCompletion:(PrestoCallback)completion {
//	[self.target addCompletion:completion];
//}

#pragma mark -

// should we allow completions on sources or just objects?
//- (PrestoSource *)addCompletion:(PrestoCallback)completion {
//	
//}

- (void)transformRequest {
	// i'm really not sure if we should do global or local first here.
	NSArray *transformers = [self.requestTransformers arrayByAddingObjectsFromArray:self.target.manager.requestTransformers];
	
	for ( PrestoRequestTransformer transformer in transformers )
		transformer( self.request );
}

- (id)transformResponse:(id)jsonObject {
	// We transform the responses locally first, which allows specific responses to be transformed into a common form before any global response transformers are applied. Global response transformers are not a commonly expected case though, unlike global request transformers which can handle things like authentication, etc.
	NSArray *transformers = [self.responseTransformers arrayByAddingObjectsFromArray:self.target.manager.responseTransformers];
	
	for ( PrestoResponseTransformer transformer in transformers )
		jsonObject = transformer( jsonObject );
	
	return jsonObject;
}

#pragma mark -

- (BOOL)isEqual:(id)object {
	if ( ![object isKindOfClass:[PrestoSource class]] )
		return NO;
	
	PrestoSource *other = (PrestoSource *)object;
	
	BOOL dataEqual = YES;
	
	if ( self.payload )
		dataEqual = self.payload == other.payload; // this does reference equality--should we actually compare the serialized payloads instead? will that ever happen?
		// note that we *don't* want to use isEqual here because that will generally only compare the identities of the objects, not their actual serialized data
	else if ( self.payloadData )
		dataEqual = [self.payloadData isEqualToData:other.payloadData];
	
	return dataEqual && [self.url.absoluteString isEqualToString:other.url.absoluteString] && [self.method isEqualToString:other.method];
}

- (NSString *)description {
	return [NSString stringWithFormat:@"%@%@ %@ %@", self.isLoading ? @"⌛" : @"", self.error ? @"⛔" : ( self.isLoaded ? @"✅" : @"◽" ), self.method ?: @"GET", self.url.absoluteString];
}

@end

#pragma mark - PrestoMetadata

@interface PrestoMetadata ()

@property (weak, nonatomic) id weakTarget;

@end

@implementation PrestoMetadata

+ (id)instantiateClass:(Class)class withDictionary:(NSDictionary *)dict {
	if ( class == nil )
		return nil;
	id result = [[class alloc] init];
//	NSAssert( [result isKindOfClass:[RemoteObject class]], @"The class ‘%@’ does not derive from RemoteObject.", class );
	[result loadWithDictionary:dict];
	return result;
}

#pragma mark -

- (instancetype)init {
	self = [super init];
	if ( self ) {
		// NOTE: keep this constructor as lightweight as possible as metadata instances may be created often
		self.manager = [Presto defaultInstance];
	}
	return self;
}

#pragma mark - Properties

- (id)target {
	// TODO: if no target, create using known type information
	// either an instance of an object class, json nsarray/nsdictionary,
	// or an array of a specific class
	
	// TODO: we also need to make sure any references to "target" in this class do so knowing that an instance could be created, and checking weakTarget otherwise

	__strong id strongTarget = self.weakTarget;
	
	if ( !strongTarget ) {
		if ( self.targetClass )
			strongTarget = [[self.targetClass alloc] init];
		else
			strongTarget = [[NSMutableDictionary alloc] init];
		
		if ( LOG_VERBOSE )
			PRLog(@"Target not found; creating a new %@: %x", self.targetClass, (uint)strongTarget);
		
		objc_setAssociatedObject( strongTarget, @selector(presto), self, OBJC_ASSOCIATION_RETAIN_NONATOMIC ); // install ourself onto the target
		self.weakTarget = strongTarget;
		
		for ( PrestoCallbackRecord* callback in self.completions )
			callback.strongTarget = strongTarget;
		
		for ( PrestoCallbackRecord* dependency in self.dependencies )
			dependency.weakTarget = strongTarget;
		
		[self loadTarget]; // loads it if there is a payload waiting
	}
	
	return strongTarget;
}

- (Class)targetClass {
	__strong id strongTarget = self.weakTarget;
	
	if ( strongTarget )
		return [strongTarget class];
	else
		return _targetClass;
}

- (BOOL)isLoading {
	return self.source.isLoading;
//	for ( PrestoSource* source in self.sources ) {
//		if ( source.loadingTime != nil )
//			return YES;
//	}
//	
//	return NO;
}

- (BOOL)isLoaded {
	return self.source.isLoaded;
//	if ( self.sources.count == 0 )
//		return NO; // we don't consider an object with no source to be loaded
	
//	for ( PrestoSource* source in self.sources ) {
//		if ( source.loadedTime == nil )
//			return NO;
//	}
//	
//	return YES;
}

- (BOOL)isCompleted {
	return self.source.isCompleted;
//	if ( self.sources.count == 0 )
//		return NO;
	
//	for ( PrestoSource *source in self.sources ) {
//		if ( !source.isCompleted )
//			return NO;
//	}
//	
//	return YES;
}

- (BOOL)loadingSince:(NSDate *)date {
	return self.source.isLoading && [self.source.loadingTime compare:date] == NSOrderedAscending;
//	for ( PrestoSource *source in self.sources ) {
//		
//			return YES;
//	}
//	return NO;
}

- (NSError *)error {
	return self.source.error;
//	for ( PrestoSource* source in self.sources ) {
//		if ( source.error || ( source.statusCode != 200 && source.statusCode != 0 ) )
//			return source.error ?: [NSError new]; // create error for status code?
//	}
//	return nil;
}

- (void)setSource:(PrestoSource *)source {
	if ( [_source isEqual:source] ) {
		if ( LOG_VERBOSE )
			PRLog(@"Presto Notice: Source set to an equivalent value. Ignoring.");
		return;
	}
	
	source.target = self;
	_source = source;
	
	// this should probably be moved into setUrl eventually
	// if there are any observers, load the object immediately
	if ( self.completions.count || self.dependencies.count ) {
		// this is wrapped in a dispatch_async so any further metadata configuration can happen on the current thread before it is kicked off
		// (in fact perhaps all loads should be async??)
		dispatch_async(dispatch_get_main_queue(), ^{
			[self load];
		});
	}
}

- (NSInteger)statusCode {
	return self.source.statusCode;
}

- (void)setRefreshInterval:(NSTimeInterval)refreshInterval {
	self.source.refreshInterval = refreshInterval;
//	for ( PrestoSource *source in self.sources ) {
//		source.refreshInterval = refreshInterval;
//	}
}

- (void)setArrayClass:(Class)arrayClass {
	_arrayClass = arrayClass;
	if ( arrayClass )
		self.targetClass = [NSMutableArray class];
}

- (NSMutableArray *)completions {
	if ( _completions == nil )
		_completions = [NSMutableArray new];
	return _completions;
}

- (NSMutableArray *)dependencies {
	if ( _dependencies == nil )
		_dependencies = [NSMutableArray new];
	return _dependencies;
}

//- (void)setIsLoading:(BOOL)isLoading {
//	if ( isLoading ) {
//		_loadingTime = [NSDate date];
////		PRLog(@"Setting %@ to LOADING at %f", [self description], [_loadingTime timeIntervalSinceReferenceDate]);
//	} else
//		_loadingTime = nil;
//}
//
//- (void)setIsLoaded:(BOOL)isLoaded {
//	if ( isLoaded ) {
//		_loadedTime = [NSDate date];
//		if ( [self.target respondsToSelector:@selector(objectLoaded)] )
//			[self.target objectLoaded];
//	} else
//		_loadedTime = nil;
//}

//- (void)setIdentity:(NSURL *)identity {
//	[self setIdentity:identity load:NO]; // default is not to immediately load (use loadFromURL: for that)
//}
//
//- (void)setIdentity:(NSURL *)identity load:(BOOL)load {
//	if ( ![self.identity isEqual:identity] ) {
//		_identity = identity;
//		self.isLoaded = NO; // reset because we changed its identity
//	}
//	
//	if ( load )
//		[self reload:YES]; // force a reload (ok?)
//}

//- (void)setError:(NSError *)error {
//	BOOL newError = YES;// error.code != self.error.code; // i don't think this is reliable yet
//	_error = error;
//	
//	if ( LOG_ERRORS && self.error || self.statusCode != 200 )
//	
////	if ( self.error && self.callbacks.count )
//	if ( self.error || ( self.statusCode != 200 && self.statusCode != 0 ) ) { // status code of 0 means it hasn't been loaded via a URL request
//		if ( LOG_ERRORS )
//			PRLog(@"*** Error %d loading object %@:\n%@", (int)self.statusCode, self.target, self.error);
//		
//		[self callFailureBlocks:newError];
//	}
//}

#pragma mark -

//- (PrestoSource *)addSource:(NSURL *)url {
//	return [self addSource:url withMethod:nil object:nil requestTransformer:nil responseTransformer:nil];
//}
//
//- (PrestoSource *)addSource:(NSURL *)url withMethod:(NSString *)method object:(id)object requestTransformer:(PrestoRequestTransformer)requestTransformer responseTransformer:(PrestoResponseTransformer)responseTransformer {
//	// TODO: we really ought to make sources a unique set; seems URLs are distinct even if they have the same value??
//	// for now just delete any previous source with the same url
//	PrestoSource* source = [PrestoSource new];
//	source.target = self;
//	source.url = url;
//	source.httpMethod = method ?: @"GET";
//	source.parameterObject = object;
//	if ( requestTransformer )
//		[source.requestTransformers addObject:requestTransformer];
//	if ( responseTransformer )
//		[source.responseTransformers addObject:responseTransformer];
//	[self.sources addObject:source];
//	return source;
//}
//
//- (PrestoSource *)setSource:(NSURL *)url {
//	return [self setSource:url withMethod:nil object:nil];
//}
//
//- (PrestoSource *)setSource:(NSURL *)url withMethod:(NSString *)method object:(id)object {
//}

//- (PrestoSource *)addSource:(PrestoSource *)source {
//	source.target = self;
//	self.source = source;
////	for ( PrestoSource *existingSource in [self.sources copy] ) {
////		if ( [existingSource.url.absoluteString isEqualToString:source.url.absoluteString] ) {
////			[self.sources removeObject:existingSource];
//////			break;
////		}
////	}
////	[self.sources addObject:source];
//	return source;
//}
//
//- (PrestoMetadata *)setSource:(PrestoSource *)source {
//	[self.sources removeAllObjects];
//	[self addSource:source];
//	return self;
//}

//- (PrestoSource *)addURL:(NSURL *)url {
//	PrestoSource *source = [PrestoSource sourceWithURL:url];
//	[self addSource:source];
//	return source;
//}

// deprecate and clean this up
//- (PrestoMetadata *)setURL:(NSURL *)url {
////	for ( PrestoSource *source in self.sources ) {
////		source.target = nil; // invalidates the source
////	}
////	[self.sources removeAllObjects];
//	[self addSource:[PrestoSource sourceWithURL:url]];
//	return self;
//}

// these are temp until i deprecate PrestoSource
//- (PrestoMetadata *)withMethod:(NSString *)method {
//	[self.source withMethod:method];
//	return self;
//}

- (PrestoMetadata *)withPayload:(id)payload {
	self.source.payload = payload;
	return self;
}

- (PrestoMetadata *)withPayloadData:(NSData *)payloadData {
	self.source.payloadData = payloadData;
	return self;
}

- (PrestoMetadata *)withPayloadString:(NSString *)payloadString {
	self.source.payloadData = [payloadString dataUsingEncoding:NSUTF8StringEncoding];
	return self;
}

- (PrestoMetadata *)withRequestTransformer:(PrestoRequestTransformer)transformer {
	[self.source.requestTransformers addObject:transformer];
	return self;
}

- (PrestoMetadata *)withResponseTransformer:(PrestoResponseTransformer)transformer {
	[self.source.responseTransformers addObject:transformer];
	return self;
}

#pragma mark -

//- (void)loadFromURL:(NSURL *)url {
////	PrestoSource *source = [self addSource:url];
////	[self loadFromSource:source force:YES];
////	return source;
////	return [self loadFromURL:url withMethod:nil object:nil requestTransformer:nil responseTransformer:nil];
////	[self setURL:url];
////	self.source = [PrestoSource sourceWithURL:url];
//	[self loadFromURL:url onComplete:nil];
//}
//
//- (void)loadFromURL:(NSURL *)url onComplete:(PrestoCallback)completion {
////	[self setURL:url];
////	self.source = [PrestoSource sourceWithURL:url];
//	[self getFromURL:url];
//	[self load];
//	if ( completion )
//		[self onComplete:completion];
//}

//- (PrestoMetadata *)loadFromURL:(NSURL *)url withMethod:(NSString *)method object:(id)object {
//	return [self loadFromURL:url withMethod:method object:object requestTransformer:nil responseTransformer:nil];
//}

//- (PrestoSource *)loadFromURL:(NSURL *)url withRequestTransformer:(PrestoRequestTransformer)requestTransformer responseTransformer:(PrestoResponseTransformer)responseTransformer {
//	return [self loadFromURL:url withMethod:nil object:nil requestTransformer:requestTransformer responseTransformer:responseTransformer];
//}

//- (PrestoSource *)loadFromURL:(NSURL *)url withMethod:(NSString *)method object:(id)object requestTransformer:(PrestoRequestTransformer)requestTransformer responseTransformer:(PrestoResponseTransformer)responseTransformer {
////	PrestoSource *source = [self addSource:url withMethod:method object:object requestTransformer:requestTransformer responseTransformer:responseTransformer];
//	[self loadFromSource:[PrestoSource sourceWithURL:url method:method object:object requestTransformer:requestTransformer responseTransformer:responseTransformer] force:YES];
//	return self;
//}

// this is currently very limited as it doesn't quite fit in with the overall design
// we need to unify this with the object loading
//- (void)loadProperty:(NSString *)propertyName fromURL:(NSURL *)url {
//	[self.sources removeObjectForKey:propertyName];
//	
//	PrestoSource *source = [PrestoSource new];
//	source.url = url;
//	source.targetProperty = propertyName;
////	source.callback = callback;
//	// anything else??
//	self.sources[propertyName] = source;
//	[self loadFromSource:source force:YES];
//}

- (void)load {
//	[self loadWithCompletion:nil force:NO];
	[self load:NO];
}

- (void)load:(BOOL)force {
	[self loadFromSource:self.source force:force];
}

// we might consider making this a config property instead/in addition
- (void)loadIfOlderThan:(NSTimeInterval)age {
	if ( [[self.source.loadedTime dateByAddingTimeInterval:age] compare:[NSDate date]] == NSOrderedAscending )
		[self load:YES]; // not sure if we need to force it
}

- (void)loadWithCompletion:(PrestoCallback)completion {
	[self load];
	
	// we should probably record the timestamp above before we load
	[self onComplete:completion];
}

- (void)loadWithCompletion:(PrestoCallback)success failure:(PrestoCallback)failure {
	[self load];
	
	[self onComplete:success failure:failure];
}

// TODO: find somewhere better for this
//- (void)testConnection {
//	Reachability* reachability = [Reachability reachabilityForInternetConnection];
////	PRLog(@"Testing connection...");
//	if ( reachability.currentReachabilityStatus == NotReachable ) {
//		if ( [self.manager.delegate respondsToSelector:@selector(connectionDropped)] )
//			[self.manager.delegate connectionDropped];
////		[self showConnectionWarning]; // FIXME: figure out how to do this
//		// TODO: offload this to some delegate/callback handler
////		if ( false/*connectionNotice == nil*/ ) {
////			switch ( self.primarySource.error.code ) {
////				default:
////				case kCFURLErrorNotConnectedToInternet:
//////					connectionNotice = [HUD showAlertWithTitle:@"No Connection" text:@"Your device does not appear to be connected to the internet. Please check your connection and come back."];
////					break;
////			
//////				case kCFURLErrorCannotFindHost:
//////				case kCFURLErrorCannotConnectToHost:
//////					connectionNotice = [HUD showAlertWithTitle:@"Cannot Reach Server" text:@"I am having trouble reaching the mobile server. The server may be down or there may be something wrong with your internet connection."];
//////					break;
////			}
////		} else {
//////			[connectionNotice show:NO]; // make sure it stays visible (and isn't overridden by another HUD call)
////		}
//	} else {
//		PRLog(@"Connection verified.");
//		if ( [self.manager.delegate respondsToSelector:@selector(connectionEstablished)] )
//			[self.manager.delegate connectionEstablished];
////		[self hideConnectionWarning]; // FIXME: figure out how to do this
//		[self.connectionTestTimer invalidate];
//		[self reloadWithCompletion:nil force:YES];
//	}
//}

- (PrestoMetadata *)getFromURL:(NSURL *)url {
	self.source = [PrestoSource sourceWithURL:url method:@"GET" payload:nil];
	return self;
}

- (PrestoMetadata *)putToURL:(NSURL *)url {
	PrestoMetadata *result = [PrestoMetadata new];
	__strong id strongTarget = self.weakTarget;
	result.source = [PrestoSource sourceWithURL:url method:@"PUT" payload:strongTarget ?: self];
	return result;
}

- (PrestoMetadata *)postToURL:(NSURL *)url {
	PrestoMetadata *result = [PrestoMetadata new];
	__strong id strongTarget = self.weakTarget;
	result.source = [PrestoSource sourceWithURL:url method:@"POST" payload:strongTarget ?: self];
	return result;
}

- (PrestoMetadata *)deleteFromURL:(NSURL *)url {
	PrestoMetadata *result = [PrestoMetadata new];
	__strong id strongTarget = self.weakTarget;
	result.source = [PrestoSource sourceWithURL:url method:@"DELETE" payload:strongTarget ?: self];
	return result;
}

- (PrestoMetadata *)getSelf {
	[self load];
	return self;
}

- (PrestoMetadata *)loadAs:(NSObject *)object {
	// TODO: we *need* to copy the whole metadata over (including observers), not just the source
	((NSObject *)self.target).presto.source = object.presto.source;
	object.presto.source = nil;
	[((NSObject *)self.target).presto load];
	return self;
}

// TODO: do we really need a force parameter?
// also can we get rid of the source parameter now that objects only have one source?
// maybe just rename loadSource
- (void)loadFromSource:(PrestoSource *)source force:(BOOL)force {
	self.source = source;
	
	if ( ( source.isLoading && !force ) || !source.url )
		return; // already loading
	
	source.isLoading = YES;
	source.request = [NSMutableURLRequest requestWithURL:source.url];
	[source.request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
	[source.request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
	
	if ( source.method && ![source.method isEqualToString:@"GET"] ) {
		source.request.HTTPMethod = source.method;
		PrestoMetadata *payloadMetadata = source.payload && [source.payload isKindOfClass:[PrestoMetadata class]] ? (PrestoMetadata *)source.payload : source.payload.presto;
		source.request.HTTPBody = payloadMetadata ? [[payloadMetadata toJSONString:NO] dataUsingEncoding:NSUTF8StringEncoding] : source.payloadData;
	}
	
	[source transformRequest];

	if ( LOG_PAYLOADS )
		PRLog(@"▶ %@ %@%@", source.request.HTTPMethod, source.request.URL.absoluteString, source.payload || source.payloadData ? [NSString stringWithFormat:@"\n%@", [[NSString alloc] initWithData:source.request.HTTPBody encoding:NSUTF8StringEncoding]] : @"");
	
	__weak __block typeof(self) weakSelf = self;
	
	self.manager.activeRequests++;
	
	// i should really consider rewriting this to use NSURLConnection objects
//	NSURLConnection* connection = [NSURLConnection connectionWithRequest:request delegate:self];
	// TODO: set source.connection?
	[NSURLConnection sendAsynchronousRequest:source.request queue:[NSOperationQueue mainQueue] completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
		__strong typeof(weakSelf) strongSelf = weakSelf;
		__strong id strongTarget = strongSelf.target;
		
		strongSelf.manager.activeRequests--; // FIXME: this can technically not be called if weakSelf disappears, leaving activeRequests in an incorrect state
			
		BOOL changed = !source.lastPayload || ![data isEqualToData:source.lastPayload]; // TODO: reenable this
		
		source.isLoading = NO; // works better up here in case any of the callbacks register further callbacks
		source.error = connectionError;
		source.statusCode = ((NSHTTPURLResponse*)response).statusCode;
		source.lastPayload = data;
		
		if ( !source.error && source.statusCode != 200 ) // what about statusCode == 0?
			source.error = [NSError errorWithDomain:@"PrestoErrorDomain" code:source.statusCode userInfo:@{NSLocalizedDescriptionKey:[NSHTTPURLResponse localizedStringForStatusCode:source.statusCode]}]; // TODO: improve this
		
		// this is apparently how NSURLConnection reports 401? (lame)
		if ( connectionError.code == kCFURLErrorUserCancelledAuthentication ) {
			if ( !source.statusCode )
				source.statusCode = 401;
			
			if ( [self.manager.delegate respondsToSelector:@selector(authenticationFailed)] )
				[self.manager.delegate authenticationFailed]; // so apps can handle a global log-out action if desired
		}
		
		NSString* jsonString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
		if ( LOG_PAYLOADS ) {
			PRLog(@"◀ %d %@ %@\n%@", (int)source.statusCode, source.request.HTTPMethod, source.url.absoluteString, jsonString);
		}
		
		if ( !strongSelf || !strongTarget ) {
			if ( LOG_ZOMBIES )
				PRLog(@"Presto! NOTICE: Target of source %@ has disappeared. Response will be ignored.", source);
			return; // object has disappeared
		}
		
		if ( source.error || source.statusCode != 200 ) {
			// TODO: add more error codes
			if ( connectionError.code == kCFURLErrorNotConnectedToInternet
					|| connectionError.code == kCFURLErrorCannotConnectToHost
					|| connectionError.code == kCFURLErrorCannotFindHost
					|| connectionError.code == kCFURLErrorTimedOut ) {
				if ( LOG_VERBOSE )
					PRLog(@"No connection (%d). Retrying.", (int)connectionError.code);
				self.manager.connectionDropped = YES;
				if ( [self.manager.delegate respondsToSelector:@selector(connectionDropped)] )
					[self.manager.delegate connectionDropped];
				// this is a special case representing an offline phone
				// rather than fail, call a special handler and keep polling
				// the reachability implementation was actually better because it was instantly reactive
				// perhaps we should set the timeout to something less than 60 seconds by default
				// or at least allow this to be customized. (we may have to switch to NSURLConnection)
				dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
					[strongSelf loadFromSource:source force:YES];
				});
				return;
			}
			[strongSelf callFailureBlocks:YES]; // fix this parameter?
		} else {
			if ( changed )
				[self loadTarget];
			[strongSelf callSuccessBlocks:changed];
		}
		
//		if ( !source.error && source.statusCode == 200 ) {
//		}
		if ( source.isLoading )
			NSAssert(!source.isLoading, @"source should not be loading here!");
		
//		if ( !source.targetProperty ) {
//		if ( changed && [strongTarget respondsToSelector:@selector(objectDidLoad)] ) {
//			[strongTarget objectDidLoad];
//		}
//		}
		
//		if ( source.callback ) {
//			// pretty sure we're not using this--do we want source callbacks??
//			prestoCallback callback = source.callback;
//			source.callback = nil;
//			callback(); // ok??
//		}
	}];
}

- (void)loadTarget {
	if ( !self.source.lastPayload || !self.source.lastPayload.length )
		return; // nothing to load
	
	NSError* jsonError;
	id jsonObject = [NSJSONSerialization JSONObjectWithData:self.source.lastPayload options:0 error:&jsonError];

	if ( self.manager.connectionDropped ) {
		self.manager.connectionDropped = NO;
		if ( [self.manager.delegate respondsToSelector:@selector(connectionEstablished)] )
			[self.manager.delegate connectionEstablished];
	}
	if ( jsonObject ) {
		jsonObject = [self.source transformResponse:jsonObject]; // or do we want to store jsonObject on the response and just call [transformResponse]?
		[self loadWithJSONObject:jsonObject];
		self.source.isLoaded = YES;
		
		NSAssert(self.source.error == nil, @"Source error should be nil here.");
	}
}

- (void)loadWithJSONString:(NSString *)json {
	NSError* jsonError;
	id jsonObject = [NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding] options:0 error:&jsonError];
	
	[self loadWithJSONObject:jsonObject];
}

- (void)loadWithJSONObject:(id)jsonObject {
//	__strong id strongTarget = self.weakTarget;
//	
//	if ( !strongTarget )
//		return; // disappeared--this doesn't really make sense anymore that we can create the new target

	id strongTarget = self.target;
		
//	NSLog(@"strongSelf.arrayClass: %@", self.arrayClass);
//	jsonObject = [self.manager transformResponse:jsonObject forClass:self.arrayClass ?: [strongTarget class]]; // improve this with a better response transformer associated with endpoint
//	jsonObject = 

	if ( [jsonObject isKindOfClass:[NSDictionary class]] ) {
//				if ( source.targetProperty ) {
//					[strongSelf loadProperty:source.targetProperty withObject:jsonObject];
////					[strongSelf callSuccessBlocks:YES]; // TODO: improve this
//				} else
		[self loadWithDictionary:jsonObject];
//		[source.serializationKeys addObjectsFromArray:[(NSDictionary *)jsonObject allKeys]]; // this is kind of a temp hack until we have a better solution
	} else if ( [jsonObject isKindOfClass:[NSArray class]] ) {
//				if ( source.targetProperty ) { // TODO: remove targetProperty entirely
//					[strongSelf loadProperty:source.targetProperty withObject:jsonObject];
////					[strongSelf callSuccessBlocks:YES]; // TODO: improve this
//				} else {
			if ( ![strongTarget isKindOfClass:[NSMutableArray class]] ) {
				if ( LOG_WARNINGS )
					PRLog(@"Presto! WARNING: Array responses must be loaded into instances of NSMutableArray.");
			}
			[self loadWithArray:jsonObject];
//				}
	} else {
		if ( LOG_ERRORS )
			PRLog(@"Presto! ERROR: Unsupported JSON object (%@) in response for %@.", [jsonObject class], [strongTarget class]);
//		source.error = [NSError new];
//				source.error = [[NSError alloc] initWithDomain:[NSString stringWithFormat:@"Unsupported JSON object (%@) in response for %@.", [jsonObject class], self.identity.absoluteString] code:-1 userInfo:nil];
//				strongSelf.error = [NSError new]; // could improve this but it's not an expected case
	}
}

// should this be on source?
- (BOOL)loadWithDictionary:(NSDictionary *)dictionary {
//	__strong id strongTarget = self.weakTarget;
//	
//	if ( !strongTarget )
//		return; // disappeared--this doesn't really make sense anymore that we can create the new target
	
	id strongTarget = self.target;
	
	if ( [strongTarget respondsToSelector:@selector(objectWillLoad:)] )
		[strongTarget objectWillLoad:dictionary];
	
	BOOL changed = NO; // not really sure if we need/want this anymore (yes we do!)
	
//	self.dictionary = dictionary; // store pre-transformed version? (makes sense)
	if ( [strongTarget isKindOfClass:[NSMutableDictionary class]] ) {
		[(NSMutableDictionary *)strongTarget addEntriesFromDictionary:dictionary];
	} else {
		for ( NSString* key in dictionary ) {
			NSString *propertyName = [self.manager propertyNameForField:key forClass:[self.target class]];
	//		Class class = [self.target class];
	//		NSString* propertyName = [self propertyNameForFieldName:key];
			id value = [dictionary valueForKey:key];
			
			// TODO: improve this (is primarySource even safe?)
	//		[self.primarySource.serializationKeys addObject:propertyName];
			
			changed = [self loadProperty:propertyName withObject:value] || changed;
		}
	}
	
	if ( [strongTarget respondsToSelector:@selector(objectDidLoad)] )
		[strongTarget objectDidLoad];
	
//	if ( [self.target respondsToSelector:@selector(objectLoaded)] )
//		[self.target objectLoaded]; // verify
//	self.isLoaded = YES;
//	if ( self.error != nil )
//		NSAssert(self.error == nil, @"Error should be nil here!");
//	self.error = nil;
//	[self callSuccessBlocks:changed];
	return changed;
}

- (BOOL)loadWithArray:(NSArray *)array {
	BOOL changed = NO;
	NSMutableArray *strongTarget = self.target;
	NSMutableArray *resultState = [NSMutableArray arrayWithCapacity:array.count];
	
	NSAssert( [strongTarget isKindOfClass:[NSMutableArray class]], @"Cannot call loadWithArray: on anything other than NSMutableArray." );
	
	if ( !self.arrayClass && LOG_WARNINGS ) {
		PRLog(@"Presto! Warning: Loading an array without presto.arrayClass. The array will be loaded with raw JSON objects (NSArray/NSDictionary). Use the arrayOfClass: method to let Presto know what class the array should be filled with.");
	}
	
	if ( [strongTarget respondsToSelector:@selector(objectWillLoad:)] )
		[(id)strongTarget objectWillLoad:array];
	
	int lastIndex = 0;
	
	for ( id elem in array ) {
		// there may be some unintentional duplication of logic here and loadProperty
		if ( self.arrayClass && [elem isKindOfClass:[NSDictionary class]] ) {
			NSObject *instance = [[self.arrayClass alloc] init];
			[instance.presto loadWithDictionary:elem];
			
			// (experimental) this algorithm is now optimized for stable order arrays, but should still work in all cases
			BOOL found = NO;
			NSUInteger count = strongTarget.count;
			for ( int i = lastIndex; i < count && i != (lastIndex - 1) % count; i = (i + 1) % count ) {
				NSObject *existing = strongTarget[i];
				if ( [existing isEqual:instance] ) {
					if ( LOG_VERBOSE )
						PRLog(@"Presto Notice: Found existing object in array (%@). Will load in place.", [existing description]);
					found = YES;
					changed = [existing.presto loadWithDictionary:elem] || changed; // make sure it's ok to not call loadwithjsonobject // also this shoudl return BOOL changed
					[resultState addObject:existing];
					[strongTarget removeObjectAtIndex:i]; // we don't technically need to remove the element, but it should make subsequent iterations quicker (unless removing itself is costly, i honestly don't know)
					lastIndex = i;
					break;
				}
			}
			
			if ( !found ) {
				changed = YES;
				[resultState addObject:instance];
			}
		} else {
			[resultState addObject:elem]; // just add it directly (no multidimensional arrays yet)
		}
	}
	
	NSAssert(resultState.count == array.count, @"Array count mismatch!");
	
	// if there are any elements left in strongTarget, they have since been removed
	if ( strongTarget.count )
		changed = YES;
	
	[strongTarget removeAllObjects];
	[strongTarget addObjectsFromArray:resultState];

	// this is not likely, but supports subclassing of NSArray
	if ( [strongTarget respondsToSelector:@selector(objectDidLoad)] )
		[(id)strongTarget objectDidLoad];
	
	return changed;
}

// returns "changed"
- (BOOL)loadProperty:(NSString *)propertyName withObject:(id)value {
	BOOL changed = NO;
	
	// get the type of the property from the current class
	// http://stackoverflow.com/a/3497822/238948
	
	// i don't think this takes into account inheritance; yeah it does, nevermind
	objc_property_t propType = nil;
	Class class = [self.target class];
//	while ( propType == nil && class != nil ) {
		propType = class_getProperty( class, [propertyName UTF8String] );
//		if ( propType )
//			break;
//		class = [class superclass];
//	}
	if ( propType == nil ) {
		if ( LOG_WARNINGS )
			[self.manager warnProperty:propertyName forClass:class valueClass:[value class]];
		return NO;
	}
	
	Class propertyClass, protocolClass;
	if ( [value isKindOfClass:[NSDictionary class]] || [value isKindOfClass:[NSArray class]] ) {
		NSString* typeString = [NSString stringWithUTF8String:property_getAttributes( propType )];
		NSString* typeAttribute = [typeString componentsSeparatedByString:@","][0];
		NSString* typeName = [typeAttribute substringWithRange:NSMakeRange(3, [typeAttribute length] - 4)];
		long protocolIndex = [typeName rangeOfString:@"<"].location; // 0 if typeName is nil
		if ( protocolIndex != 0 && protocolIndex != NSNotFound ) {
			// TODO: improve and unify with toDictionary
			NSString* protocolName = [typeName substringWithRange:NSMakeRange(protocolIndex + 1, [typeName rangeOfString:@">"].location - protocolIndex - 1)];
//			if ( [protocolName containsString:@","] )
//				NSLog(@"Protocol: %@", protocolName);
			NSString* protocolTypeName = protocolName;//[self typeNameForProtocolName:protocolName]; // TODO: reimplement
			protocolClass = NSClassFromString( protocolTypeName );
			if ( protocolClass == nil && LOG_WARNINGS ) {
				PRLog(@"Presto! Warning: protocolClass not determinable from protocol name ‘%@’.", protocolName);
			}
			typeName = [typeName substringToIndex:protocolIndex];
		}
		propertyClass = NSClassFromString( typeName );
	}
	
	id existingValue = [self.target valueForKey:propertyName];
	
	if ( [value isKindOfClass:[NSDictionary class]] ) {
		if ( [propertyClass isSubclassOfClass:[NSDictionary class]] ) {
//		if ( propertyClass == [NSDictionary class] || propertyClass == [NSMutableDictionary class] ) {
			// the class property is a dictionary rather than an object type
			// there are two cases here--either a protocol provides an object type to rehydrate or we simply treat the value of the property as a dictionary
			if ( protocolClass ) {
				if ( existingValue && [existingValue isKindOfClass:[NSObject class]] ) {
					// always favor in-place loading whenever possible
					changed = [((NSObject *)existingValue).presto loadWithDictionary:value];
				} else {
					changed = YES;
					NSMutableDictionary* valueDict = [NSMutableDictionary dictionaryWithCapacity:[(NSDictionary*)value count]];
					// not sure if this would benefit from being optimized with block enumeration
					for ( NSString* key in [value allKeys] ) {
						id elem = value[key];
						if ( ![elem isKindOfClass:[NSDictionary class]] ) {
							PRLog(@"Presto WARNING: Object type dictionary properties (declared via a protocol) must have dictionaries as its values." );
							[valueDict setObject:elem forKey:key];
							continue;
						}
						id childObject = [PrestoMetadata instantiateClass:protocolClass withDictionary:elem];
						[valueDict setObject:childObject forKey:key];
					}
					[self.target setValue:valueDict forKey:propertyName];
				}
			} else {
				changed = YES; // TODO: recursively compare dictionaries? isEqualToDictionary: is not enough i don't think
				[self.target setValue:value forKey:propertyName];
			}
		} else {
			// assume it is an embedded object
			if ( existingValue && [existingValue isKindOfClass:propertyClass] )
				changed = [((NSObject *)existingValue).presto loadWithDictionary:value];
			else {
				changed = YES; // it's not reliable enough to use isEqual: because that will often just compare identities; we need to know if the *data* (full contents) of the object has changed or not (which we can't currently know unless we were to record sub-payloads or something)
				id childObject = [PrestoMetadata instantiateClass:propertyClass withDictionary:value];
//				if ( ![existingValue isEqual:childObject] ) // this is not reliable enough
//					changed = YES;
				[self.target setValue:childObject forKey:propertyName];
			}
		}
	} else if ( [value isKindOfClass:[NSArray class]] && protocolClass != nil ) {
		NSMutableArray *childArray;
		BOOL new = NO;
		
		if ( existingValue && [existingValue isKindOfClass:[NSMutableArray class]] )
			childArray = existingValue;
		else {
			new = YES;
			changed = YES;
			childArray = [NSMutableArray arrayWithCapacity:[(NSArray*)value count]];
//			[self.target setValue:childArray forKey:propertyName]; // ok to add before it's loaded? this may not be a good idea with key-value observers!
		}
		
		childArray.presto.arrayClass = protocolClass;
		changed = [childArray.presto loadWithArray:value] || changed;
		
		if ( new )
			[self.target setValue:childArray forKey:propertyName];
	} else {
		// TODO: error handling
		if ( value == [NSNull null] )
			value = nil;
		// wrap this in @try?
//		id existingValue = [self.target valueForKey:propertyName];
		if ( existingValue == ValueForUndefinedKey) { // see valueForUndefinedKey:
			if ( LOG_WARNINGS )
				PRLog(@"Presto! Warning: Property ‘%@’ not found in data model %@.", propertyName, [self.target class]);
		} else {
			if ( ![existingValue isEqual:value] ) // FIXME: doesn't work for nil
				changed = YES;
			@try {
				[self.target setValue:value forKey:propertyName];
			}
			@catch ( NSException* exception ) {
				PRLog(@"Exception attempting to set value for key ‘%@’:\n%@", propertyName, exception);
			}
		}
	}
	
	return changed;
}

#pragma mark -

- (id)objectOfClass:(Class)class {
	self.targetClass = class;
	self.arrayClass = nil;
	
	return self.target;
}

- (id)arrayOfClass:(Class)class {
	self.targetClass = [NSMutableArray class];
	self.arrayClass = class;
	
	return self.target;
}

// TODO: add dictionaryOfClass??

#pragma mark -

- (NSString *)toJSONString {
	return [self toJSONString:YES];
}

- (NSString *)toJSONString:(BOOL)pretty {
	return [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:[self toJSONObject] options:pretty ? NSJSONWritingPrettyPrinted : 0 error:nil] encoding:NSUTF8StringEncoding];
}

- (id)toJSONObject {
	if ( !self.weakTarget )
		return nil;
	if ( [self.target isKindOfClass:[NSArray class]] ) {
		NSMutableArray *result = [NSMutableArray arrayWithCapacity:((NSArray *)self.target).count];
		for ( NSObject *elem in (NSArray *)self.target ) {
			[result addObject:[elem.presto toJSONObject]];
		}
		return [NSArray arrayWithArray:result]; // immutable
	} else
		return [self toDictionary];
}

- (NSDictionary *)toDictionary {
	return [self toDictionaryComplete:NO];
}

- (NSDictionary *)toDictionaryComplete:(BOOL)complete {
	if ( !self.weakTarget )
		return nil;
	if ( [self.target isKindOfClass:[NSDictionary class]] )
		return self.target; // we're already a dictionary! this avoids attempting to serialize NSDictionary's properties
	
	NSMutableArray* properties = [NSMutableArray new];
	Class class = self.targetClass;
	
	while ( class && class != [NSObject class] ) {
		uint count;
		objc_property_t* c_properties = class_copyPropertyList( class, &count );
		for ( int i = 0; i < count; i++ )
			[properties addObject:[NSValue valueWithBytes:&c_properties[i] objCType:@encode(objc_property_t)]]; // TODO: do we need to free this ever? documentation isn't clear
		free( c_properties );
		class = [class superclass];
	}
	
	NSMutableDictionary* dictionary = [NSMutableDictionary dictionaryWithCapacity:properties.count];
	NSMutableArray *serializationKeys;
	if ( [self.target respondsToSelector:@selector(serializingKeys)] )
		serializationKeys = [[self.target serializingKeys] mutableCopy];
	
	for ( NSValue* value in properties ) {
		objc_property_t c_property;
		[value getValue:&c_property];
		NSString* propertyName = [NSString stringWithCString:property_getName( c_property ) encoding:NSUTF8StringEncoding];
		if ( [propertyName isEqualToString:@"presto"] )
			continue;
		else if ( serializationKeys && ![serializationKeys containsObject:propertyName] ) {
			NSLog(@"skipping property “%@” as it's not in serializableKeys.", propertyName);
			continue;
		}
		
		Class protocolClass;
		NSString* typeString = [NSString stringWithUTF8String:property_getAttributes( c_property )];
		NSString* typeAttribute = [typeString componentsSeparatedByString:@","][0];
		NSString* typeName = [typeAttribute substringWithRange:NSMakeRange(3, [typeAttribute length] - 4)];
		NSString* propertyType = [typeAttribute substringFromIndex:1];
		long protocolIndex = [typeName rangeOfString:@"<"].location; // 0 if typeName is nil
		if ( protocolIndex != 0 && protocolIndex != NSNotFound ) {
			NSString* protocolName = [typeName substringWithRange:NSMakeRange(protocolIndex + 1, [typeName rangeOfString:@">" options:NSBackwardsSearch].location - protocolIndex - 1)];
//			if ( [protocolName containsString:@","] )
//				NSLog(@"Protocol: %@", protocolName);
			NSArray* protocolNames = [protocolName componentsSeparatedByString:@"><"];
			if ( !complete && [protocolNames containsObject:@"DoNotSerialize"] )
				continue;
			NSString* protocolTypeName = protocolName;//[self typeNameForProtocolName:protocolName]; // TODO: reimplement
			protocolClass = NSClassFromString( protocolTypeName );
			if ( protocolClass == nil && LOG_WARNINGS ) {
				PRLog(@"Presto! Warning: protocolClass not determinable from protocol name ‘%@’.", protocolName);
			}
			typeName = [typeName substringToIndex:protocolIndex];
		}
//		propertyClass = NSClassFromString( typeName );
		
//		NSLog(@"propertyName: %@ class: %@", propertyName, [self.target class]);//temp
//		Class testClass = NSClassFromString(NSStringFromClass([self.target class]));
		if ( !complete && ![self.manager shouldPropertyBeSerialized:propertyName forClass:self.targetClass] )
			continue;
//		BOOL skip = NO;
		// we should be able to get rid of this when we have proper serialization key handling
//		for ( PrestoSource *source in self.sources ) {
			if ( self.source.serializationKeys.count && ![self.source.serializationKeys containsObject:propertyName] ) {
				continue;
//				break;
			}
//		}
		BOOL isBool = strcmp( [propertyType UTF8String], @encode(BOOL) ) == 0;
//		if ( skip )
//			continue;
//		PRLog(@"propertyName: %@", propertyName);
		// TODO: add white/blacklisting
		NSString* fieldName;// = [self.target fieldNameForPropertyName:propertyName];
		// TODO: wrap this in a function
		fieldName = [self.manager fieldNameForProperty:propertyName forClass:[self.target class]];
//		PRLog(@"propertyName: %@", propertyName);
		
		id value = [self.target valueForKey:propertyName];
		
		// convert BOOL into NSNumber so it is serialized as "true" or "false":
		if ( isBool ) {
//			NSLog(@"BOOL!!!!!!!!!!!!!!!!!! %@", value);
			if ( [value isEqualToNumber:@(0)] )
				value = @NO;
			else if ( [value isEqualToNumber:@(1)] )
				value = @YES;
//			value = value ? @YES : @NO;
		}
		
		if ( [value isKindOfClass:[Presto class]] || [value isKindOfClass:[PrestoMetadata class]] || [value isKindOfClass:[PrestoSource class]] )
			continue; // don't serialize internal objects
		
		if ( value == nil || value == [NSNull null] )
			[dictionary setObject:[NSNull null] forKey:fieldName];
		else if ( [NSJSONSerialization isValidJSONObject:@[value]] ) { // the value has to be wrapped in something in order for isValidJSONObject to work properly; bizarre implementation --lmurray2015
			[dictionary setObject:value forKey:fieldName];
		} else if ( [value isKindOfClass:[NSArray class]] ) {
			NSMutableArray *arrayValue = [NSMutableArray arrayWithCapacity:((NSArray *)value).count];
			for ( NSObject *object in (NSArray *)value ) {
				[arrayValue addObject:object.presto.toDictionary];
			}
			[dictionary setObject:arrayValue forKey:fieldName];
		} else {
			[dictionary setObject:[[(NSObject *)value presto] toDictionary] forKey:fieldName];
		}
		
		[serializationKeys removeObject:propertyName]; // ok??
	}
//	free( properties );
	
	for ( NSString* missingProperty in serializationKeys )
		[dictionary setObject:[NSNull null] forKey:missingProperty];
	
	return dictionary;
}

#pragma mark -

- (PrestoMetadata *)onComplete:(PrestoCallback)completion {
	[self onComplete:completion failure:nil];
	return self;
}

//- (PrestoMetadata *)addCompletion:(PrestoCallback)block withTarget:(id)target {
//	[self addCompletion:block failure:nil withTarget:target];
//	return self;
//}

//- (PrestoMetadata *)addCompletion:(PrestoCallback)success failure:(PrestoCallback)failure {
//	[self addCompletion:success failure:failure withTarget:nil];
//	return self;
//}

// TODO: move this to prestoMetadata:
//- (void)addCompletion:(prestoCallback)success failure:(prestoCallback)failure withTarget:(id)target {
//	[self addCompletion:success failure:failure forProperty:nil withTarget:target];
////	if ( self.isLoaded && !self.isLoading ) { // if we are loading, wait until the load finishes (?)
////		// should we wrap this in a dispatch_async?
//////		PRLog(@"Calling success block immediately for object %@", self);
////		success(); // call immediately
////	} else {
////		prestoCallbackRecord *rec = [prestoCallbackRecord new];
////		rec.target = target;
////		if ( target )
////			rec.hasTarget = YES;
////		rec.success = success;
////		rec.failure = failure;
////		[self.primarySource.callbacks addObject:rec];
////		
//////		PRLog(@"Registering callback for %@.\nCallbacks: %@", self, self.callbacks);
////		
////		if ( !self.isLoading )
////			[self reload];
////	}
//}

- (PrestoMetadata *)onChange:(PrestoCallback)dependency {
	return [self onChange:dependency withTarget:nil];
}

// TODO: rename "target" here to something else... lifeline... something
- (PrestoMetadata *)onChange:(PrestoCallback)dependency withTarget:(id)target {
	if ( [self.targetClass isSubclassOfClass:[NSArray class]] && ![self.targetClass isSubclassOfClass:[NSMutableArray class]] && !self.source.url && !self.arrayClass ) {
		[self addSetDependency:dependency withTarget:target];
		return self;
	}

//	PrestoSource* source = [self sourceForProperty:property];
	PrestoCallbackRecord* rec = [PrestoCallbackRecord new];
	if ( target ) {
		rec.weakTarget = target;
		rec.hasTarget = YES;
	}
	rec.success = dependency;
	[self.dependencies addObject:rec];
	
	// slight hack here: if we add a dependency and there are no sources at all, we should probably still call it (allows for manually controlling an object that may not necessarily be loaded from the server)
	if ( self.isLoaded ) // used to have && !isLoading, but i removed this to support changed flag
		dependency( self.target );
	else if ( !self.isLoading )
		[self load];
	
	return self;
}

- (PrestoMetadata *)onComplete:(PrestoCallback)success failure:(PrestoCallback)failure {
	// if this is called on an immutable array, we assume it is an array of presto objects because immutable arrays can't be loaded dynamically
	if ( [self.targetClass isSubclassOfClass:[NSArray class]] && ![self.targetClass isSubclassOfClass:[NSMutableArray class]] && !self.source.url && !self.arrayClass ) {
		[self addSetCompletion:success failure:failure];
		return self;
	}
//	PrestoSource* source = [self sourceForProperty:property];
	if ( self.isLoaded && !self.isLoading ) {
		success( self.target ); // would there be any benefit in wrapping this in an async?
	} else {
		PrestoCallbackRecord* rec = [PrestoCallbackRecord new];
//		if ( target ) {
//			rec.weakTarget = target;
//			rec.hasTarget = YES;
//		}
		rec.strongTarget = self.weakTarget; // completions keep the target alive and are guaranteed to fire (in theory)
		rec.success = success;
		rec.failure = failure;
//		[self.manager.globalCompletions addObject:rec];
		[self.completions addObject:rec];
		
		if ( !self.isLoading ) {
			dispatch_async(dispatch_get_main_queue(), ^{
				[self load];
			});
		}
	}
	return self;
}

// TODO: verify that this does not leak memory by keeping arbitrary arrays around indefinitely.
- (void)addSetCompletion:(PrestoCallback)success failure:(PrestoCallback)failure {
	NSArray *arrayTarget = (NSArray *)self.target;
	// there might be a better way to do this
	// if this object has its own source/definition, treat it like a normal Presto object
	// this method is for subscribing to multiple dependencies at once for a completion or group dependency.
//	if ( objc_getAssociatedObject( self, @selector(presto) ) && self.presto.source.url ) {
//		[self.presto addCompletion:success];
//		return;
//	}

	// this implementation assumes that an object cannot go from a loaded state to a non-loaded state
//	__block id strongSelf = self; // this used to be weak but it didn't work (array needs to be kept alive until its members complete)
	// TODO: the above may not be needed now that completions keep strong references
	__block NSDate* timestamp = [NSDate date];
	
//	PRLog(@"Attaching ARRAY completion at timestamp: %f", [timestamp timeIntervalSinceReferenceDate]);
	
	void (^interceptor)() = ^{
//		__strong typeof(weakSelf) strongSelf = weakSelf;
		if ( !arrayTarget ) { // is this even possible anymore?
//			PRLog(@"Array completion strongSelf has disappeared! Did this array already complete??");
			return; // the array no longer exists; abort
		}
		
		BOOL allLoaded = YES;
		
		for ( NSObject *elem in arrayTarget ) {
//			if ( ![elem isKindOfClass:[RemoteObject class]] )
//				continue; // skip any non-remote object elements (or fail??)
//			RemoteObject* obj = (RemoteObject*)elem;
//			if ( obj.loading )
//				PRLog(@"shouldn't be still loading!!");
			if ( !elem.presto.isCompleted || [elem.presto loadingSince:timestamp] ) {
				if ( LOG_VERBOSE )
					PRLog(@"Array element %@ %@ failed completion check. array timestamp: %f", elem.presto, elem, [timestamp timeIntervalSinceReferenceDate]);
				allLoaded = NO;
				break;
			}
		}
		
		if ( allLoaded ) {
//			PRLog(@"Array completed. Calling success and setting strongSelf to nil.");
			BOOL allSucceeded = YES;
			for ( NSObject *elem in arrayTarget ) {
				if ( elem.presto.error ) {
					allSucceeded = NO;
					break;
				}
			}
			if ( allSucceeded || !failure )
				success( arrayTarget );
			else
				failure( arrayTarget );
//			arrayTarget = nil; // this was above success() does it need to be?
		}
	};
	
	for ( NSObject *elem in self.target ) {
//		if ( ![elem isKindOfClass:[RemoteObject class]] )
//			continue; // see above
		
		[elem.presto onComplete:interceptor];
	}
}

- (void)addSetDependency:(PrestoCallback)dependency withTarget:(id)target {
	@throw @"implement";
}

// abstract this to addCompletionForSource or something internally so we can reuse it
// or we can just pass nil for property
//- (void)addCompletion:(prestoCallback)success failure:(prestoCallback)failure forProperty:(NSString *)property withTarget:(id)target {
//}
//
//- (void)onChange:(prestoCallback)dependency forProperty:(NSString *)property withTarget:(id)target {
//
//}

#pragma mark -

// this method manually calls dependency blocks, but not completions
// TODO: this logic is duplicated; should be moved into callDependencyBlocks:(BOOL)changed
- (void)signalChange {
	__weak __block typeof(self) weakSelf = self;
	
	for ( PrestoCallbackRecord* rec in self.dependencies ) {
		__strong id target = rec.strongTarget ?: rec.weakTarget;
		if ( target || !rec.hasTarget ) {
			dispatch_async(dispatch_get_main_queue(), ^{
				__strong typeof(weakSelf) strongSelf = weakSelf;
				rec.success( strongSelf.target );
			});
		}
		// FIXME: we have to remove the callback records for dead targets
	}
}

#pragma mark -

- (void)callSuccessBlocks:(BOOL)changed {
//	if ( !self.isLoaded )
//		return;
	
//	PRLog(@"Calling success blocks for %@\nCallbacks: %d Dependencies: %d", self, self.callbacks.count, self.dependencies.count);
	
	// this is weird like this because a callback can result in modifications to the callbacks array; so we need to do it in waves like this
	// hopefully this won't result in an infinite loop
	
	// TODO: do we still need to wrap this in a loop? what if we copy the array and clear it before calling any callbacks--will additional callbacks registered within another handler still be called?
	
	// TODO: we need to check the timestamp of a callback against the timestamp of the request
	// we need to figure out these timing issues so that we never have a "stalled" callback
	// this seems to be especially true for array callbacks
	__weak __block typeof(self) weakSelf = self;
	
	while ( self.completions.count ) {
		NSArray* completions = [self.completions copy];
		[self.completions removeAllObjects];
		for ( PrestoCallbackRecord* rec in completions ) {
			__strong id target = rec.strongTarget ?: rec.weakTarget;
			if ( target || !rec.hasTarget ) {
				// the following dispatch prevents reentrancy which can cause problems
				
				// FIXME: make sure this dispatch is enabled for release!
//				dispatch_async(dispatch_get_main_queue(), ^{
					__strong typeof(weakSelf) strongSelf = weakSelf;
					rec.success( strongSelf.target );
//				});
			}
		}
//		[self.callbacks removeObjectsInArray:callbacks];
//		PRLog(@"Done success block wave, removing called callbacks (%d remaining).", self.callbacks.count);
	}
	
	// FIXME: using changed here could be dangerous if the dependency was added after the last change
	// actually maybe not, because it should have been called immediately anyway
	// what if it was loading when added, and now the load is completed!
	if ( changed ) { // TODO: maybe changed should actually be an NSDate so we can know if it's changed *since* a dependency was added. yes, do this.
		for ( PrestoCallbackRecord* rec in self.dependencies ) {
			__strong id target = rec.strongTarget ?: rec.weakTarget;
			if ( target || !rec.hasTarget ) {
				dispatch_async(dispatch_get_main_queue(), ^{
					__strong typeof(weakSelf) strongSelf = weakSelf;
					rec.success( strongSelf.target );
				});
			}
			// FIXME: we have to remove the callback records for dead targets
		}
	}
}

- (void)callFailureBlocks:(BOOL)changed {
//	PRLog(@"Calling failure blocks for %@\nCallbacks: %d Dependencies: %d", self, self.callbacks.count, self.dependencies.count);

	__weak __block typeof(self) weakSelf = self;
	
	while ( self.completions.count ) { // see above
		NSArray* callbacks = [self.completions copy];
		[self.completions removeAllObjects];
		for ( PrestoCallbackRecord* rec in callbacks ) {
			__strong id target = rec.strongTarget ?: rec.weakTarget;
			if ( target || !rec.hasTarget ) {
				dispatch_async(dispatch_get_main_queue(), ^{
					__strong typeof(weakSelf) strongSelf = weakSelf;
					if ( rec.failure )
						rec.failure( strongSelf.target );
					else
						rec.success( strongSelf.target );
				});
			}
		}
	}
	
	// i'm actually not sure we should be calling dependencies on failure at all. completions, yes, because they need to complete, but calling dependencies really only makes sense if the load was successful, no?
	
//	if ( changed ) {
	// TODO: remove calling dependencies on failure
	for ( PrestoCallbackRecord* rec in self.dependencies ) {
		NSLog(@"calling dependency in failure handler %@", rec);
		__strong id target = rec.strongTarget ?: rec.weakTarget;
		if ( target || !rec.hasTarget ) {
			dispatch_async(dispatch_get_main_queue(), ^{
				__strong typeof(weakSelf) strongSelf = weakSelf;
				if ( rec.failure )
					rec.failure( strongSelf.target );
				else
					rec.success( strongSelf.target );
			});
		}
		// FIXME: we have to remove the callback records for dead targets
	}
//	}
}

#pragma mark -

- (NSString *)description {
	// other cool symbols: 🔄⚠⛔◽🔳🔲✅☐☒☑
	NSString *typeName = [NSString stringWithFormat:@"%@%@", self.targetClass, self.arrayClass ? [NSString stringWithFormat:@"<%@>", self.arrayClass] : @""];
	NSString *statusIcon = self.error ? @"⛔" : ( self.isLoaded ? @"✅" : ( self.weakTarget ? @"🔲" : @"◽" ) );
	return [NSString stringWithFormat:@"%@%@ %@ 0x%x %@ %@", self.isLoading ? @"⌛" : @"", statusIcon, typeName, (uint)self.weakTarget, self.source.method, self.source.url.absoluteString];
}

@end

#pragma mark - NSObject (PrestoMetadata)

@implementation NSObject (PrestoMetadata)

- (PrestoMetadata *)presto {
	if ( [self isKindOfClass:[PrestoMetadata class]] )
		return (id)self; // experimental. allows calling .presto without worry
	
	if ( objc_getAssociatedObject( self, @selector(presto) ) == nil )
		[self setupMetadata];
	
	return objc_getAssociatedObject( self, @selector(presto) );
}

- (void)setupMetadata {
	if ( [self isKindOfClass:[PrestoMetadata class]] )
		NSAssert( ![self isKindOfClass:[PrestoMetadata class]], @"Presto! metadata cannot be installed recursively upon itself. This is probably an indication something else is wrong somewhere. Set a breakpoint here and trace back.");
//	if ( LOG_VERBOSE )
//		PRLog(@"Installing Presto metadata on %@ %x", [self class], (uint)self);
	objc_setAssociatedObject( self, @selector(presto), [PrestoMetadata new], OBJC_ASSOCIATION_RETAIN_NONATOMIC );
	self.presto.weakTarget = self; // weak reference
}

// this could potentially break shit--do we really need this?
- (id)valueForUndefinedKey:(NSString *)key {
	return ValueForUndefinedKey; // a special object that indicates the runtime was not able to find a property with the requested key on the current object
}

@end

#pragma mark - NSArray (Presto)

@implementation NSArray (Presto)

+ (id)arrayOfClass:(Class)class {
	NSMutableArray *array = [NSMutableArray new];
	array.presto.arrayClass = class;
	return array;
}

//+ (id)arrayOfClass:(Class)class loadedFromURL:(NSURL *)url {
//	NSArray *array = [self arrayOfClass:class];
//	[array.presto loadFromURL:url];
//	return array;
//}

#pragma mark -

//- (void)addCompletion:(PrestoCallback)success {
//	[self addCompletion:success withTarget:nil];
//}

// we should actually move this into Metadata and expose it optionally like NSObject



@end

//#pragma mark - NSMutableArray (presto)
//
//@implementation NSMutableArray (presto)
//
////+ (instancetype)newWithMemberType:(Class)class; {
////
////}
//
////+ (instancetype)newWithMemberType:(Class)class {
////	NSMutableArray* new = [NSMutableArray new];
//////	new.memberType = class;
////	return new;
////}
//
//- (void)loadFromURL:(NSURL *)url elementClass:(Class)class {
//	self.presto.elementClass = class;
//	[self.presto loadFromURL:url];
//}
//
//@end

#undef PRLog