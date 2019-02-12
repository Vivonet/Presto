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
//  https://github.com/devios1/Presto

#import <objc/runtime.h>
#import <UIKit/UIKit.h>
#import "Presto.h"

static const BOOL LOG_PAYLOADS = YES;
static const BOOL LOG_HEADERS = NO;
static const BOOL LOG_WARNINGS = YES;
static const BOOL LOG_ERRORS = YES;
static const BOOL LOG_VERBOSE = NO;
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
	if (_defaultInstance == nil) {
		_defaultInstance = [Presto new];
	}
	
	return _defaultInstance;
}

+ (Class)defaultErrorClass {
	return [Presto defaultInstance].defaultErrorClass;
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

+ (void)setDefaultErrorClass:(Class)defaultErrorClass {
	[Presto defaultInstance].defaultErrorClass = defaultErrorClass;
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

+ (void)registerInstance:(id)instance {
	[[Presto defaultInstance] registerInstance:instance];
}

#pragma mark -

+ (PrestoMetadata *)getFromURL:(NSURL *)url {
	PrestoMetadata *result = [PrestoMetadata new];
	result.source = [PrestoSource new];
	result.source.url = url;
	result.source.method = @"GET";
	return result;
}

+ (PrestoMetadata *)putToURL:(NSURL *)url {
	PrestoMetadata *result = [PrestoMetadata new];
	result.source = [PrestoSource new];
	result.source.url = url;
	result.source.method = @"PUT";
	return result;
}

+ (PrestoMetadata *)postToURL:(NSURL *)url {
	PrestoMetadata *result = [PrestoMetadata new];
	result.source = [PrestoSource new];
	result.source.url = url;
	result.source.method = @"POST";
	return result;
}

+ (PrestoMetadata *)deleteFromURL:(NSURL *)url {
	PrestoMetadata *result = [PrestoMetadata new];
	result.source = [PrestoSource new];
	result.source.url = url;
	result.source.method = @"DELETE";
	return result;
}

#pragma mark -

- (instancetype)init {
	self = [super init];
	if (self) {
		self.fieldToPropertyMappings = [NSMutableDictionary new];
		self.propertyToFieldMappings = [NSMutableDictionary new];
		self.requestTransformers = [NSMutableArray new];
		self.responseTransformers = [NSMutableArray new];
		self.serializationKeys = [NSMutableDictionary new];
		self.warnedKeys = [NSMutableDictionary new];
		self.classIndex = [NSMutableDictionary new];
		
		self.trackParentObjects = YES;
		self.showActivityIndicator = YES;
		self.ignoreNulls = YES;
	}
	return self;
}

#pragma mark -

- (void)processJSONObject:(id)object forClass:(Class)class depth:(int)depth {
	if (object == nil || class == nil)
		return;
	
	assert(depth > 0);
	
	if ([object isKindOfClass:NSMutableArray.self]) {
		NSMutableArray *array = object;
		for (int i = 0; i < [array count]; i++) {
			id elem = [array objectAtIndex:i];
			
			if (depth > 1) {
				[self processJSONObject:elem forClass:class depth:depth - 1];
			} else { // depth == 1
				if (![elem isKindOfClass:NSDictionary.self]) {
					if (LOG_WARNINGS)
						PRLog(@"pRESTo Warning: Supplied class depth does not correspond to a dictionary in the response. Actual type: %@", [elem class]);
					continue;
				}
				
				id instance = [self instantiateClass:class withDictionary:elem];
				[array replaceObjectAtIndex:i withObject:instance];
			}
		}
	} else if ([object isKindOfClass:NSMutableDictionary.self]) {
		NSMutableDictionary *dictionary = object;
		for (NSString *key in dictionary) {
			id elem = dictionary[key];
			
			if (depth > 1) {
				[self processJSONObject:elem forClass:class depth:depth - 1];
			} else { // depth == 1
				if (![elem isKindOfClass:NSDictionary.self]) {
					if (LOG_WARNINGS)
						PRLog(@"pRESTo Warning: Supplied class depth does not correspond to a dictionary in the response. Actual type: %@", [elem class]);
					continue;
				}
				
				id instance = [self instantiateClass:class withDictionary:elem];
				dictionary[key] = instance;
			}
		}
	} else {
		if (LOG_ERRORS)
			PRLog(@"pRESTo Error: Unsupported or immutable JSON object.");
	}
}

- (id)instantiateClass:(Class)class withDictionary:(NSDictionary *)dict {
	if (class == nil)
		return nil;
	
	// TODO: the efficiency here could be improved; we are currently performing in the worst case two loadWithDictionary calls for every call to this method
	
	NSObject<PrestoDelegate> *result = [[class alloc] init];
	
	if ([result respondsToSelector:@selector(objectWillLoad:)])
		[result objectWillLoad:dict]; // ok??
	
	[result.presto loadWithDictionary:dict];
	
	id<NSCopying> key = nil;
	if ([result respondsToSelector:@selector(identifyingKey)])
		key = [(id<PrestoDelegate>)result identifyingKey];
	if (key) {
//		if (self.classIndex[class] == nil)
//			self.classIndex[(id<NSCopying>)class] = [NSMapTable strongToWeakObjectsMapTable]; // TODO: verify!!
		NSMapTable *instanceIndex = self.classIndex[class];
		if ([instanceIndex objectForKey:key] != nil) {
			if (LOG_VERBOSE)
				PRLog(@"Presto: Found existing singleton instance %@:%@.", class, key);
			result = [instanceIndex objectForKey:key];
			[result.presto loadWithDictionary:dict]; // load the existing object with the (presumably) latest data
		} else
			[self registerInstance:result];
	}
	
	return result;
}

- (void)registerInstance:(id)instance {
	if (instance == nil)
		return;
	
	Class class = [instance class];
	id<NSCopying> key = nil;
	if ([instance respondsToSelector:@selector(identifyingKey)])
		key = [(id<PrestoDelegate>)instance identifyingKey];
	if (key) {
		if (self.classIndex[class] == nil)
			self.classIndex[(id<NSCopying>)class] = [NSMapTable strongToWeakObjectsMapTable]; // TODO: verify!!
		NSMapTable *instanceIndex = self.classIndex[class];
		if (LOG_VERBOSE)
			PRLog(@"Presto: Registering singleton instance %@:%@.", class, key);
		[instanceIndex setObject:instance forKey:key];
	}
}

#pragma mark -

- (void)setActiveRequests:(NSInteger)activeRequests {
	_activeRequests = activeRequests;
	
	if (self.showActivityIndicator) {
		dispatch_async(dispatch_get_main_queue(), ^{
			[UIApplication sharedApplication].networkActivityIndicatorVisible = self.activeRequests > 0;
		});
	}
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

- (void)addGlobalResponseTransformer:(PrestoResponseTransformer)transformer {
//	[self addResponseTransformer:transformer forClass:[NSObject class]];
	[self.responseTransformers addObject:transformer];
}

- (void)mapRemoteField:(NSString *)field toLocalProperty:(NSString *)property forClass:(Class)class {
//	id<NSCopying> key = (id<NSCopying>)class ?: [NSNull null];
	
	if (self.fieldToPropertyMappings[class] == nil) {
		[(NSMutableDictionary *)_fieldToPropertyMappings setObject:[NSMutableDictionary new] forKey:(id<NSCopying>)class];
	}
	[(NSMutableDictionary *)self.fieldToPropertyMappings[class] setObject:property forKey:field];
	
	if (self.propertyToFieldMappings[class] == nil) {
		[(NSMutableDictionary *)_propertyToFieldMappings setObject:[NSMutableDictionary new] forKey:(id<NSCopying>)class];
	}
	[(NSMutableDictionary *)self.propertyToFieldMappings[class] setObject:field forKey:property];
}

- (void)addSerializationKey:(NSString *)key forClass:(Class)class {
	if (self.serializationKeys[class] == nil) {
		[(NSMutableDictionary *)_serializationKeys setObject:[NSMutableSet new] forKey:(id<NSCopying>)class];
	}
	[(NSMutableSet *)_serializationKeys[class] addObject:key];
}

- (void)addSerializationKeys:(NSArray *)keys forClass:(Class)class {
	for (NSString *key in keys)
		[self addSerializationKey:key forClass:class];
}

#pragma mark -

- (NSString *)propertyNameForField:(NSString *)fieldName forClass:(Class)class {
	NSString *propertyName;
	while (class != nil) {
		NSDictionary *fieldToPropertyMappings = self.fieldToPropertyMappings[class];
		if (fieldToPropertyMappings && fieldToPropertyMappings[fieldName] != nil)
			propertyName = fieldToPropertyMappings[fieldName];
		// should we break? does it make sense to keep going?
		class = [class superclass];
	}
	return propertyName ?: fieldName;
}

- (NSString *)fieldNameForProperty:(NSString *)propertyName forClass:(Class)class {
	NSString *fieldName;
	while (class != nil) {
		NSDictionary *propertyToFieldMappings = self.propertyToFieldMappings[class];
		if (propertyToFieldMappings && propertyToFieldMappings[propertyName] != nil)
			fieldName = propertyToFieldMappings[propertyName];
		// should we break? does it make sense to keep going?
		class = [class superclass];
	}
	return fieldName ?: propertyName;
}

- (BOOL)shouldPropertyBeSerialized:(NSString *)propertyName forClass:(Class)class {
	NSArray* ignoreKeys = @[@"superclass", @"hash", @"debugDescription"]; // never serialize these
	
	if ([ignoreKeys containsObject:propertyName])
		return NO;
	
	NSMutableSet *serializationKeys = self.serializationKeys[class];
	
	if (!serializationKeys || [serializationKeys containsObject:propertyName])
		return YES;
	else
		return NO;
}

#pragma mark -

- (void)warnProperty:(NSString *)propertyName forClass:(Class)class valueClass:(Class)valueClass {
	if (!LOG_WARNINGS)
		return;
	
	if (self.warnedKeys[class] == nil) {
		self.warnedKeys[(id<NSCopying>)class] = [NSMutableSet new];
	}
	
	if (![self.warnedKeys[class] containsObject:propertyName]) {
		PRLog(@"pRESTo Warning: Property ‘%@’ (%@) not found in class %@.", propertyName, valueClass, class);
		[self.warnedKeys[class] addObject:propertyName];
	}
}

@end

#pragma mark - PrestoCallbackRecord

@implementation PrestoCallbackRecord

@end

@implementation PrestoCompletionRecord

@end

@implementation PrestoDependencyRecord

@end

#pragma mark - PrestoSource

@implementation PrestoSource

+ (instancetype)sourceWithURL:(NSURL *)url method:(NSString *)method payload:(id)payload {
	if (!url) {
		if (LOG_ERRORS)
			PRLog(@"Presto Error: No URL supplied for source.");
		return nil;
	}
	
	PrestoSource *source = [PrestoSource new];
	source.url = url;
	source.method = method ?: @"GET";
	
	if (payload && [payload isKindOfClass:[NSString class]])
		source.payloadData = [((NSString *)payload) dataUsingEncoding:NSUTF8StringEncoding];
	else
		source.payload = payload;
	
	return source;
}

- (instancetype)init {
	self = [super init];
	if (self) {
//		self.serializationKeys = [NSMutableArray new];
		
		// TODO: change these to lazy-load
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
	if (isLoading) {
		_loadingTime = [NSDate date];
	} else {
		_loadingTime = nil;
	}
}

- (void)setIsLoaded:(BOOL)isLoaded {
	if (isLoaded) {
		_loadedTime = [NSDate date];
		self.error = nil; // does this make sense??
//		if ([self.target respondsToSelector:@selector(objectLoaded)])
//			[self.target objectLoaded];
	} else
		_loadedTime = nil;
}

- (BOOL)isCompleted {
	return self.isLoaded || self.error ;//|| self.statusCode != 200;
}

- (void)setError:(NSError *)error {
	_error = error;
	
	if (error && LOG_ERRORS)
		PRLog(@"ERROR: %d %@\n%@", (int)self.statusCode, self, self.error);
}

- (void)setRefreshInterval:(NSTimeInterval)refreshInterval {
	_refreshInterval = refreshInterval;
	
	if (_refreshInterval != INFINITY && _refreshInterval != 0) { // both 0 and INFINITY mean never
		__block __weak typeof(self) weakSelf = self;
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(self.refreshInterval * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
			typeof(weakSelf) strongSelf = weakSelf;
			if (strongSelf) {
				[strongSelf.target reload]; // verify .target
				strongSelf.refreshInterval = strongSelf.refreshInterval; // queue next refresh
			}
		});
	}
}

#pragma mark -

- (void)transformRequest {
	// i'm really not sure if we should do global or local first here.
	NSArray *transformers = [self.requestTransformers arrayByAddingObjectsFromArray:self.target.manager.requestTransformers];
	
	for (PrestoRequestTransformer transformer in transformers)
		transformer(self.request);
}

- (id)transformResponse:(id)jsonObject {
	// We transform the responses locally first, which allows specific responses to be transformed into a common form before any global response transformers are applied. Global response transformers are not a commonly expected case though, unlike global request transformers which can handle things like authentication, etc.
	NSArray *transformers = [self.responseTransformers arrayByAddingObjectsFromArray:self.target.manager.responseTransformers];
	
	for (PrestoResponseTransformer transformer in transformers)
		jsonObject = transformer(jsonObject);
	
	return jsonObject;
}

#pragma mark -

- (BOOL)isEqual:(id)object {
	if (![object isKindOfClass:[PrestoSource class]])
		return NO;
	
	PrestoSource *other = (PrestoSource *)object;
	
	BOOL dataEqual = YES;
	
	if (self.payload)
		dataEqual = self.payload == other.payload; // this does reference equality--should we actually compare the serialized payloads instead? will that ever happen?
		// note that we *don't* want to use isEqual here because that will generally only compare the identities of the objects, not their actual serialized data
	else if (self.payloadData)
		dataEqual = [self.payloadData isEqualToData:other.payloadData];
	
	return dataEqual && [self.url.absoluteString isEqualToString:other.url.absoluteString] && [self.method isEqualToString:other.method];
}

- (NSString *)description {
	return [NSString stringWithFormat:@"%@%@ %@ %@", self.isLoading ? @"⌛" : @"", self.error ? @"⛔" : (self.isLoaded ? @"✅" : @"◽"), self.method ?: @"GET", self.url.absoluteString];
}

@end

#pragma mark - PrestoMetadata

@interface PrestoMetadata ()

@property (weak, nonatomic) id weakTarget;

@end

@implementation PrestoMetadata

- (instancetype)init {
	self = [super init];
	if (self) {
		// NOTE: keep this constructor as lightweight as possible as metadata instances may be created often
		self.manager = [Presto defaultInstance];
	}
	return self;
}

#pragma mark - Properties

- (id)target {
	__strong id strongTarget = self.weakTarget;
	
	return strongTarget;
}

- (Class)targetClass {
		return [self.target class];
}

- (BOOL)isLoading {
	return self.source.isLoading;
}

- (BOOL)isLoaded {
	return !self.source || self.source.isLoaded;
}

- (BOOL)isCompleted {
	return !self.source || self.source.isCompleted;
}

- (BOOL)loadingSince:(NSDate *)date {
	return self.source.isLoading && [self.source.loadingTime compare:date] == NSOrderedAscending;
}

- (NSError *)error {
	return self.source.error;
}

- (id)errorResponse {
	return self.source.errorResponse;
}

- (void)setSource:(PrestoSource *)source {
	if ([_source isEqual:source]) {
		if (LOG_VERBOSE)
			PRLog(@"Presto: Source set to an equivalent value. Ignoring.");
		return;
	}
	
	source.target = self;
	_source = source;
	
	[self invalidate];
}

- (NSInteger)statusCode {
	return self.source.statusCode;
}

- (void)setRefreshInterval:(NSTimeInterval)refreshInterval {
	self.source.refreshInterval = refreshInterval;
}

- (NSMutableArray *)callbacks {
	if (_callbacks == nil)
		_callbacks = [NSMutableArray new];
	return _callbacks;
}

- (NSString *)lastResponseString {
	if (self.source.lastPayload)
		return [[NSString alloc] initWithData:self.source.lastPayload encoding:NSUTF8StringEncoding];
	else
		return nil;
}

- (id)lastResponseObject {
	if (self.source.lastPayload)
		return [NSJSONSerialization JSONObjectWithData:self.source.lastPayload options:NSJSONReadingMutableContainers error:nil] ?: [[NSString alloc] initWithData:self.source.lastPayload encoding:NSUTF8StringEncoding];
	else
		return nil;
}

#pragma mark -

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

- (PrestoMetadata *)withUsername:(NSString *)username password:(NSString *)password {
	// TODO: implement
	PRLog(@"This function is unimplemented!");
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

- (PrestoMetadata *)withTemplate:(NSString *)jsonTemplate {
	self.source.serializationTemplate = [NSJSONSerialization JSONObjectWithData:[jsonTemplate dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
	// TODO: add error handling
	return self;
}

#pragma mark -

// TODO: differentiate between reload (GET) and resend (PUT/POST/DELETE)?
- (PrestoMetadata *)reload {
	return [self reload:NO];
}

- (PrestoMetadata *)reload:(BOOL)force {
	[self load:force];
	return self;
}

// we might consider making this a config property instead/in addition
- (PrestoMetadata *)reloadIfOlderThan:(NSTimeInterval)age {
	if ((!self.isLoaded && !self.isLoading) || [[self.source.loadedTime dateByAddingTimeInterval:age] compare:[NSDate date]] == NSOrderedAscending)
		[self reload:YES]; // not sure if we need to force it
	return self;
}

- (PrestoMetadata *)reloadWithCompletion:(PrestoCallback)completion {
	return [[self reload] onComplete:completion];
}

- (PrestoMetadata *)reloadWithCompletion:(PrestoCallback)success failure:(PrestoCallback)failure {
	return [[self reload] onComplete:success failure:failure];
}

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
	return [self reload];
}

- (PrestoMetadata *)putSelf {
	return [[self putToURL:self.source.url] reload]; // puts and posts don't need an observer to load
}

- (PrestoMetadata *)postSelf {
	return [[self postToURL:self.source.url] reload]; // puts and posts don't need an observer to load
}

- (PrestoMetadata *)deleteSelf {
	return [[self deleteFromURL:self.source.url] reload];
}

- (PrestoMetadata *)loadWithObject:(NSObject *)object {
	// TODO: we *need* to copy the whole metadata over (including observers), not just the source
	((NSObject *)self.target).presto.source = object.presto.source;
	object.presto.source = nil;
	[((NSObject *)self.target).presto reload];
	return self;
}

- (PrestoMetadata *)appendFrom:(NSObject *)source {
	if (![self.targetClass isSubclassOfClass:[NSMutableArray class]]) {
		if (LOG_ERRORS)
			PRLog(@"pRESTo Error: appendFrom: can only be called on NSMutableArray targets.");
		return nil;
	}
	
	PrestoMetadata *result = [self loadWithObject:source];
	result.append = YES; // is it safe to set this *after* the above call? if it's guaranteed to be decoupled then yes
	
	return result;
}

#pragma mark -

- (PrestoMetadata *)deferLoad {
	self.isDeferred = YES;
	return self;
}

- (PrestoMetadata *)invalidate {
	// experimental--there is probably more we need to consider here, like if the object is currently loading or has completions
	self.source.isLoaded = NO;
	
	// if there are any observers, load the object immediately
	// TODO: should we skip this if deferLoad is true??
	if (self.callbacks.count/* self.completions.count || self.dependencies.count*/) {
		// this is wrapped in a dispatch_async so any further metadata configuration can happen on the current thread before it is kicked off
		// (in fact perhaps all loads should be async??)
		dispatch_async(dispatch_get_main_queue(), ^{
			[self reload];
		});
	}
	
	return self;
}

#pragma mark -

- (void)load:(BOOL)force {
	PrestoSource *source = self.source;
	
	if (!source.url) {
		if (LOG_VERBOSE)
			PRLog(@"Presto Notice: Attempted to load an object with no source. You may be attempting to attach a completion/dependency to the wrong object, or have forgotten to provide a source for this object.");
		return;
	}
	
	self.isDeferred = NO; // if we are presently loading, we are no longer deferred
	
	if (source.isLoading && !force)
		return; // already loading
	
	[NSObject cancelPreviousPerformRequestsWithTarget:self]; // in case we've scheduled any re-tries, cancel them
	
	source.isLoading = YES;
	source.request = [NSMutableURLRequest requestWithURL:source.url];
	[source.request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
	[source.request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
	
	if (source.method && ![source.method isEqualToString:@"GET"]) {
		source.request.HTTPMethod = source.method;
		PrestoMetadata *payloadMetadata = source.payload && [source.payload isKindOfClass:[PrestoMetadata class]] ? (PrestoMetadata *)source.payload : source.payload.presto;
		source.request.HTTPBody = payloadMetadata ? [[payloadMetadata toJSONStringWithTemplate:source.serializationTemplate prettyPrinted:NO] dataUsingEncoding:NSUTF8StringEncoding] : source.payloadData;
	}
	
	[source transformRequest];
	
	__block NSMutableString *requestHeaders = [NSMutableString new];
	if (LOG_HEADERS) {
		[source.request.allHTTPHeaderFields enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, NSString * _Nonnull obj, BOOL * _Nonnull stop) {
			[requestHeaders appendFormat:@"\n   %@: %@", key, obj];
		}];
	}

	if (LOG_PAYLOADS)
		PRLog(@"▶ %@ %@%@%@", source.request.HTTPMethod, source.request.URL.absoluteString, requestHeaders, source.payload || source.payloadData ? [NSString stringWithFormat:@"\n%@", [[NSString alloc] initWithData:source.request.HTTPBody encoding:NSUTF8StringEncoding]] : @"");
	
	__weak __block typeof(self) weakSelf = self;
	
	self.manager.activeRequests++;
	
	// i should really consider rewriting this to use NSURLConnection objects
//	NSURLConnection* connection = [NSURLConnection connectionWithRequest:request delegate:self];
	// TODO: set source.connection?
	[[[NSURLSession sharedSession] dataTaskWithRequest:source.request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable connectionError) {
		
//	}];
//	[NSURLConnection sendAsynchronousRequest:source.request queue:[NSOperationQueue mainQueue] completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
		__strong typeof(weakSelf) strongSelf = weakSelf;
//		__strong id strongTarget = strongSelf.target;
		
		strongSelf.manager.activeRequests--; // FIXME: (nonurgent) this can technically not be called if weakSelf disappears, leaving activeRequests in an incorrect state
			
		BOOL changed = !source.lastPayload || ![data isEqualToData:source.lastPayload];
		// TODO: we should consider dropping this changed flag entirely, because it's quite possible that the client state could have changed and we need to reset it to the server state even if the server state has not itself actually changed
		
		source.isLoading = NO; // works better up here in case any of the callbacks register further callbacks
		source.error = connectionError;
		source.statusCode = ((NSHTTPURLResponse*)response).statusCode;
		source.lastPayload = data;
		
		if (!source.error && source.statusCode != 200) // what about statusCode == 0?
			source.error = [NSError errorWithDomain:@"PrestoErrorDomain" code:source.statusCode userInfo:@{NSLocalizedDescriptionKey:[NSHTTPURLResponse localizedStringForStatusCode:source.statusCode]}]; // TODO: improve this
		
		// this is apparently how NSURLConnection reports 401? (lame)
		if (connectionError.code == kCFURLErrorUserCancelledAuthentication) {
			if (!source.statusCode)
				source.statusCode = 401;
			
			if ([self.manager.delegate respondsToSelector:@selector(authenticationFailed)])
				[self.manager.delegate authenticationFailed]; // so apps can handle a global log-out action if desired
		}
		
		__block NSMutableString *responseHeaders = [NSMutableString new];
		if (LOG_HEADERS) {
			[((NSHTTPURLResponse *)response).allHeaderFields enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
				[responseHeaders appendFormat:@"\n   %@: %@", key, obj];
			}];
		}
		
		NSString* jsonString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
		if (LOG_PAYLOADS) {
			PRLog(@"◀ %d %@ %@%@\n%@", (int)source.statusCode, source.request.HTTPMethod, source.url.absoluteString, responseHeaders, jsonString);
		}
		
		__strong id strongTarget = strongSelf.target;
		
		if (!strongSelf || !strongTarget) {
			if (LOG_ZOMBIES)
				PRLog(@"Presto: Target of source %@ has disappeared. Response will be ignored.", source);
//			return; // object has disappeared
		}
		
		if (source.error || source.statusCode != 200) {
			// TODO: add more error codes
			if (connectionError.code == kCFURLErrorNotConnectedToInternet
					|| connectionError.code == kCFURLErrorCannotConnectToHost
					|| connectionError.code == kCFURLErrorCannotFindHost) {
//					|| connectionError.code == kCFURLErrorTimedOut) { // it is probably not safe to resend on timeout on second thought
				if (LOG_VERBOSE)
					PRLog(@"No connection (%d). Retrying.", (int)connectionError.code);
				self.manager.connectionDropped = YES;
				if ([self.manager.delegate respondsToSelector:@selector(connectionDropped)])
					[self.manager.delegate connectionDropped];
				// this is a special case representing an offline phone
				// rather than fail, call a special handler and keep polling
				// the reachability implementation was actually better because it was instantly reactive
				// perhaps we should set the timeout to something less than 60 seconds by default
				// or at least allow this to be customized. (we may have to switch to NSURLConnection)
				source.error = nil; // we don't want this hanging around
				[weakSelf performSelector:@selector(load:) withObject:@YES afterDelay:2.0];
//				dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
//					[strongSelf load:YES];
//				});
				return;
			}
			[strongSelf loadResponse];
			[strongSelf callFailureBlocks:YES]; // fix this parameter?
		} else {
			if (changed)
				[self loadResponse];
//			[strongSelf callSuccessBlocks:changed includeCompletions:YES];
		}
		
//		if (!source.error && source.statusCode == 200) {
//		}
		if (source.isLoading)
			NSAssert(!source.isLoading, @"source should not be loading here!");
		
//		if (!source.targetProperty) {
//		if (changed && [strongTarget respondsToSelector:@selector(objectDidLoad)]) {
//			[strongTarget objectDidLoad];
//		}
//		}
	}] resume];
}

- (void)loadResponse {
	if (!self.source.lastPayload || !self.source.lastPayload.length)
		return; // nothing to load
	
	id jsonObject = [self lastResponseObject];
	
	// not sure if this is the best place for this
	if (self.manager.connectionDropped) {
		self.manager.connectionDropped = NO;
		if ([self.manager.delegate respondsToSelector:@selector(connectionEstablished)])
			[self.manager.delegate connectionEstablished];
	}
	
	if (jsonObject) {
		if (!self.source.error && self.source.statusCode == 200) {
			jsonObject = [self.source transformResponse:jsonObject]; // or do we want to store jsonObject on the response and just call [transformResponse]?
			[self loadWithJSONObject:jsonObject];
			self.source.isLoaded = YES;
			
//			NSAssert(self.source.error == nil, @"Source error should be nil here.");
		} else {
			// TODO: do we want to transform the response in the event of an error??
			id errorResponse = jsonObject;
			Class errorClass = self.errorClass ?: self.manager.defaultErrorClass;
			if (errorClass && [jsonObject isKindOfClass:[NSDictionary class]])
				errorResponse = [self.manager instantiateClass:errorClass withDictionary:jsonObject];
			// TODO: add support for arrays using errorClass as the arrayClass
			self.source.errorResponse = errorResponse;
		}
	}
}

- (BOOL)loadWithJSONString:(NSString *)json {
	// should this set the lastPayload?
	NSError* jsonError;
	id jsonObject = [NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding] options:NSJSONReadingMutableContainers error:&jsonError];
	
	return [self loadWithJSONObject:jsonObject];
}

// do we really need this anymore?
- (BOOL)loadWithJSONObject:(id)jsonObject {
//	__strong id strongTarget = self.weakTarget;
//	
//	if (!strongTarget)
//		return; // disappeared--this doesn't really make sense anymore that we can create the new target

	id strongTarget = self.target;
		
//	NSLog(@"strongSelf.arrayClass: %@", self.arrayClass);
//	jsonObject = [self.manager transformResponse:jsonObject forClass:self.arrayClass ?: [strongTarget class]]; // improve this with a better response transformer associated with endpoint
//	jsonObject =

	BOOL changed = NO;

	if ([jsonObject isKindOfClass:[NSDictionary class]]) {
//				if (source.targetProperty) {
//					[strongSelf loadProperty:source.targetProperty withObject:jsonObject];
////					[strongSelf callSuccessBlocks:YES]; // TODO: improve this
//				} else
		changed = [self loadWithDictionary:jsonObject];
//		[source.serializationKeys addObjectsFromArray:[(NSDictionary *)jsonObject allKeys]]; // this is kind of a temp hack until we have a better solution
	} else if ([jsonObject isKindOfClass:[NSArray class]]) {
//				if (source.targetProperty) { // TODO: remove targetProperty entirely
//					[strongSelf loadProperty:source.targetProperty withObject:jsonObject];
////					[strongSelf callSuccessBlocks:YES]; // TODO: improve this
//				} else {
			if (![strongTarget isKindOfClass:[NSMutableArray class]]) {
				if (LOG_WARNINGS)
					PRLog(@"pRESTo Warning: Array responses must be loaded into instances of NSMutableArray.");
			}
			changed = [self loadWithArray:jsonObject];
//				}
	} else if (!strongTarget) {
		// experimental new case: just assign the jsonObject as the target
		strongTarget = jsonObject;
		self.weakTarget = strongTarget;
		changed = true;
		[self callSuccessBlocks:true];
	} else {
		if (LOG_ERRORS)
			PRLog(@"pRESTo Error: Unsupported JSON object (%@) in response for %@.", [jsonObject class], [strongTarget class]);
//		source.error = [NSError new];
//				source.error = [[NSError alloc] initWithDomain:[NSString stringWithFormat:@"Unsupported JSON object (%@) in response for %@.", [jsonObject class], self.identity.absoluteString] code:-1 userInfo:nil];
//				strongSelf.error = [NSError new]; // could improve this but it's not an expected case
		return NO;
	}
	
//	[self callSuccessBlocks:changed];// includeCompletions:
//	if (changed) {
//		[self signalChange];
//	}
	
	return changed;
}

// returns YES if changed
// should this be on source?
- (BOOL)loadWithDictionary:(NSDictionary *)dictionary {
	if (dictionary == nil)
		return NO;
	
	if (self.nativeClass && self.classDepth > 0)
		[self.manager processJSONObject:dictionary forClass:self.nativeClass depth:self.classDepth];
	
	__strong id strongTarget = self.weakTarget;
	
	if (!strongTarget) {
		if (self.nativeClass && self.classDepth == 0) {
			strongTarget = [self.manager instantiateClass:self.nativeClass withDictionary:dictionary];
			
			if ([strongTarget respondsToSelector:@selector(objectDidLoad)]) // try to unify this with below
				[strongTarget objectDidLoad];
			
			return YES; // nothing more to do, we're fully loaded
		} else {
			strongTarget = [NSMutableDictionary dictionaryWithDictionary:dictionary];
		}
		self.weakTarget = strongTarget;
	}
	
//	if (!strongTarget)
//		return; // disappeared--this doesn't really make sense anymore that we can create the new target
	
//	id strongTarget = self.target;
	
	if ([strongTarget respondsToSelector:@selector(objectWillLoad:)])
		[strongTarget objectWillLoad:dictionary];
	
	BOOL changed = NO; // not really sure if we need/want this anymore (yes we do!)
	
//	self.dictionary = dictionary; // store pre-transformed version? (makes sense)
	if ([strongTarget isKindOfClass:[NSMutableDictionary class]]) {
//		[(NSMutableDictionary *)strongTarget addEntriesFromDictionary:dictionary];
//		changed = YES; // we have to assume this because addEntries doesn't tell us
		for (NSString* key in dictionary) {
			NSObject *value = [dictionary valueForKey:key];
			NSObject *existing = [(NSMutableDictionary *)strongTarget valueForKey:key];

			if (existing) {
				changed = [existing.presto loadWithJSONObject:value] || changed;
			} else {
				[(NSMutableDictionary *)strongTarget setObject:value forKey:key];
				changed = YES;
			}
//			if (self.nativeClass && self.classDepth > 1)
//				[value.presto withClass:self.nativeClass atDepth:self.classDepth - 1];
		}
	} else { // assume we are a custom class (which means nativeClass is already applied)
		for (NSString* key in dictionary) { // does this need allKeys?
			NSString *propertyName = [self.manager propertyNameForField:key forClass:[self.target class]];
	//		Class class = [self.target class];
	//		NSString* propertyName = [self propertyNameForFieldName:key];
			id value = [dictionary valueForKey:key];
			
			// TODO: improve this (is primarySource even safe?)
	//		[self.primarySource.serializationKeys addObject:propertyName];
			
			changed = [self loadProperty:propertyName withObject:value] || changed;
		}
	}
	
	if ([strongTarget respondsToSelector:@selector(objectDidLoad)])
		[strongTarget objectDidLoad];
	
//	if ([self.target respondsToSelector:@selector(objectLoaded)])
//		[self.target objectLoaded]; // verify
//	self.isLoaded = YES;
//	if (self.error != nil)
//		NSAssert(self.error == nil, @"Error should be nil here!");
//	self.error = nil;
	[self callSuccessBlocks:changed];
	
	return changed;
}

- (BOOL)loadWithArray:(NSArray *)array {
	if (array == nil)
		return NO;
	
	if (self.nativeClass && self.classDepth > 0)
		[self.manager processJSONObject:array forClass:self.nativeClass depth:self.classDepth];
	
	__strong NSMutableArray *strongTarget = self.weakTarget;
	
	if (!strongTarget) {
		strongTarget = [NSMutableArray new];
		self.weakTarget = strongTarget;
	}
	
	BOOL changed = NO;
//	NSMutableArray *strongTarget = self.target;
	NSMutableArray *tempResult = [NSMutableArray arrayWithCapacity:array.count];
	
	NSAssert([strongTarget isKindOfClass:[NSMutableArray class]], @"Cannot call loadWithArray: on anything other than NSMutableArray.");
	
	if ([strongTarget respondsToSelector:@selector(objectWillLoad:)])
		[(id)strongTarget objectWillLoad:array];
	
	int lastIndex = 0;
	
	for (id elem in array) {
		NSObject *instance = elem; // default to the raw array element
		// there may be some unintentional duplication of logic here and loadProperty
		if (self.nativeClass && self.classDepth == 1 && [elem isKindOfClass:[NSDictionary class]]) {
//			NSObject *instance = [[self.arrayClass alloc] init];
//			[instance.presto loadWithDictionary:elem];
			instance = [self.manager instantiateClass:self.nativeClass withDictionary:elem];
			// if we assume nativeClass only applies once, we should be done with it now
		}
			// (experimental) this algorithm is now optimized for stable order arrays, but should still work in all cases
		BOOL found = NO;
		NSUInteger count = strongTarget.count;
		for (int i = lastIndex; i < count && i != (lastIndex - 1) % count; i = (i + 1) % count) {
			NSObject *existing = strongTarget[i];
			if ([existing isEqual:instance]) {
				if (LOG_VERBOSE)
					PRLog(@"Presto: Found existing object in array (%@). Will load in place.", [existing description]);
				instance = existing;
				found = YES;
				changed = [instance.presto loadWithDictionary:elem] || changed; // make sure it's ok to not call loadwithjsonobject // also this shoudl return BOOL changed
//					[resultState addObject:existing];
				[strongTarget removeObjectAtIndex:i]; // we don't technically need to remove the element, but it should make subsequent iterations quicker (unless removing itself is costly, i honestly don't know)
				lastIndex = i;
				break;
			}
		}
			
		if (!found) {
			changed = YES;
//				[resultState addObject:instance];
		}
		
		if (self.nativeClass && self.classDepth > 1)
			[instance.presto withClass:self.nativeClass atDepth:self.classDepth - 1];
		
		// TODO: unify this somewhere
		if (self.manager.trackParentObjects)
			instance.presto.parent = strongTarget;
		
		[tempResult addObject:instance];
	}
	
	NSAssert(tempResult.count == array.count, @"Array count mismatch!");
	
	// if there are any elements left in strongTarget, they have since been removed
	if (strongTarget.count)
		changed = YES;
	
	[strongTarget removeAllObjects];
	[strongTarget addObjectsFromArray:tempResult];
	
	[self callSuccessBlocks:changed];

	// this is not likely, but supports subclassing of NSArray
	if ([strongTarget respondsToSelector:@selector(objectDidLoad)])
		[(id)strongTarget objectDidLoad];
	
	return changed;
}

// returns "changed"
// if this only applies to native classes we can assume nativeClass will already be applied before this point and won't need to be again
- (BOOL)loadProperty:(NSString *)propertyName withObject:(id)value {
	BOOL changed = NO;
	
	// get the type of the property from the current class
	// http://stackoverflow.com/a/3497822/238948
	
	// i don't think this takes into account inheritance; yeah it does, nevermind
	objc_property_t propType = nil;
	Class class = self.targetClass;//[self.target class];
//	while (propType == nil && class != nil) {
	propType = class_getProperty(class, [propertyName UTF8String]);
//		if (propType)
//			break;
//		class = [class superclass];
//	}
	if (propType == nil) {
		if (LOG_WARNINGS)
			[self.manager warnProperty:propertyName forClass:class valueClass:[value class]];
		return NO;
	}
	
	if ((value == nil || value == [NSNull null]) && self.manager.ignoreNulls) {
		if (LOG_VERBOSE)
			PRLog(@"Presto: Ignoring null value for %@.%@.", class, propertyName);
		return NO;
	}
	
	Class propertyClass, protocolClass;
	if ([value isKindOfClass:[NSDictionary class]] || [value isKindOfClass:[NSArray class]]) {
		NSString* typeString = [NSString stringWithUTF8String:property_getAttributes(propType)];
		NSString* typeAttribute = [typeString componentsSeparatedByString:@","][0];
		NSString* typeName = [typeAttribute substringWithRange:NSMakeRange(3, [typeAttribute length] - 4)];
		long protocolIndex = [typeName rangeOfString:@"<"].location; // 0 if typeName is nil
		if (protocolIndex != 0 && protocolIndex != NSNotFound) {
			// TODO: improve and unify with toDictionary
			NSString* protocolName = [typeName substringWithRange:NSMakeRange(protocolIndex + 1, [typeName rangeOfString:@">"].location - protocolIndex - 1)];
//			if ([protocolName containsString:@","])
//				NSLog(@"Protocol: %@", protocolName);
			NSString* protocolTypeName = protocolName;//[self typeNameForProtocolName:protocolName]; // TODO: reimplement
			protocolClass = NSClassFromString(protocolTypeName);
			if (protocolClass == nil && LOG_WARNINGS) {
				PRLog(@"pRESTo Warning: protocolClass not determinable from protocol name ‘%@’.", protocolName);
			}
			typeName = [typeName substringToIndex:protocolIndex];
		}
		propertyClass = NSClassFromString(typeName);
	}
	
	id existingValue = [self.target valueForKey:propertyName];
	
	if ([value isKindOfClass:[NSDictionary class]]) {
		if ([propertyClass isSubclassOfClass:[NSDictionary class]]) {
//		if (propertyClass == [NSDictionary class] || propertyClass == [NSMutableDictionary class]) {
			// the class property is a dictionary rather than an object type
			// there are two cases here--either a protocol provides an object type to rehydrate or we simply treat the value of the property as a dictionary
			if (protocolClass) {
				if (existingValue && [existingValue isKindOfClass:[NSObject class]]) {
					// always favor in-place loading whenever possible
					changed = [((NSObject *)existingValue).presto loadWithDictionary:value];
				} else {
					changed = YES;
					NSMutableDictionary* valueDict = [NSMutableDictionary dictionaryWithCapacity:[(NSDictionary*)value count]];
					// not sure if this would benefit from being optimized with block enumeration
					for (NSString* key in [value allKeys]) {
						id elem = value[key];
						if (![elem isKindOfClass:[NSDictionary class]]) {
							PRLog(@"pRESTo Warning: Object type dictionary properties (declared via a protocol) must have dictionaries as its values.");
							[valueDict setObject:elem forKey:key];
							continue;
						}
						NSObject *childObject = [self.manager instantiateClass:protocolClass withDictionary:elem];
						
						if (self.manager.trackParentObjects)
							childObject.presto.parent = valueDict;
						
						[valueDict setObject:childObject forKey:key];
					}
					[self setTargetValue:valueDict forKey:propertyName];
				}
			} else {
				changed = YES; // TODO: recursively compare dictionaries? isEqualToDictionary: is not enough i don't think
				[self setTargetValue:value forKey:propertyName];
			}
		} else {
			// assume it is an embedded object
			if (existingValue && [existingValue isKindOfClass:propertyClass])
				changed = [((NSObject *)existingValue).presto loadWithDictionary:value];
			else {
				changed = YES; // it's not reliable enough to use isEqual: because that will often just compare identities; we need to know if the *data* (full contents) of the object has changed or not (which we can't currently know unless we were to record sub-payloads or something)
				id childObject = [self.manager instantiateClass:propertyClass withDictionary:value];
//				if (![existingValue isEqual:childObject]) // this is not reliable enough
//					changed = YES;
				[self setTargetValue:childObject forKey:propertyName];
			}
		}
	} else if ([value isKindOfClass:[NSArray class]] && protocolClass != nil) {
		NSMutableArray *childArray;
		BOOL new = NO;
		
		if (existingValue && [existingValue isKindOfClass:[NSMutableArray class]])
			childArray = existingValue;
		else {
			new = YES;
			changed = YES;
			childArray = [NSMutableArray arrayWithCapacity:[(NSArray*)value count]];
//			[self setTargetValue:childArray forKey:propertyName]; // ok to add before it's loaded? this may not be a good idea with key-value observers!
		}
		
//		childArray.presto.arrayClass = protocolClass;
		[childArray.presto withClass:protocolClass atDepth:self.classDepth - 1]; // verify
		changed = [childArray.presto loadWithArray:value] || changed;
		
		if (new)
			[self setTargetValue:childArray forKey:propertyName];
	} else {
		// TODO: error handling
		if (value == [NSNull null])
			value = nil;
		// wrap this in @try?
//		id existingValue = [self.target valueForKey:propertyName];
		if (existingValue == ValueForUndefinedKey) { // see valueForUndefinedKey:
			if (LOG_WARNINGS)
				PRLog(@"pRESTo Warning: Property ‘%@’ not found in data model %@.", propertyName, [self.target class]);
		} else {
			if (![existingValue isEqual:value]) // FIXME: doesn't work for nil
				changed = YES;
			@try {
				[self setTargetValue:value forKey:propertyName];
			}
			@catch (NSException* exception) {
				PRLog(@"Exception attempting to set value for key ‘%@’:\n%@", propertyName, exception);
			}
		}
	}
	
	return changed;
}

- (void)setTargetValue:(NSObject *)value forKey:(NSString *)key {
	@try {
		[self.target setValue:value forKey:key];
		
		// parent object tracking--we only want to track the parent on "real objects"
		if (self.manager.trackParentObjects && ![value isKindOfClass:[NSNumber class]] && ![value isKindOfClass:[NSString class]])
			value.presto.parent = self.target; // experimental
	}
	@catch (NSException *exception) {
		if (LOG_WARNINGS)
			PRLog(@"pRESTo Warning: Couldn’t set %@.%@ to %@.", self.targetClass, key, value);
		
		// TODO: adding proper converters might help a lot to avoid this
		
		// TODO: if we are unable to set a property, should we abort the entire object and set it to nil on the parent target?
		// that seems like a bad idea, not sure why i suggested that
	}
	@finally {
		
	}
}

#pragma mark -

- (PrestoMetadata *)withClass:(Class)class atDepth:(int)depth {
	self.nativeClass = class;
	self.classDepth = depth;
	
	return self;
}

- (PrestoMetadata *)withErrorClass:(Class)class atDepth:(int)depth {
	self.errorClass = class;
	self.errorDepth = depth;
	
	return self;
}

#pragma mark -

- (NSString *)toJSONString {
	return [self toJSONStringWithTemplate:nil prettyPrinted:YES];
}

- (NSString *)toJSONStringWithTemplate:(id)template {
	return [self toJSONStringWithTemplate:template prettyPrinted:YES];
}

- (NSString *)toJSONStringWithTemplate:(id)template prettyPrinted:(BOOL)pretty {
	return [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:[self toJSONObjectWithTemplate:template] options:pretty ? NSJSONWritingPrettyPrinted : 0 error:nil] encoding:NSUTF8StringEncoding];
}

- (id)toJSONObject {
	return [self toJSONObjectWithTemplate:nil];
}

- (id)toJSONObjectWithTemplate:(id)template {
	if (!self.weakTarget)
		return nil;
	if ([self.target isKindOfClass:[NSArray class]]) {
		NSMutableArray *result = [NSMutableArray arrayWithCapacity:((NSArray *)self.target).count];
		
		id arraySubTemplate;
		if ([template isKindOfClass:[NSArray class]] && [template count] > 1)
			arraySubTemplate = template[0];
		
		for (NSObject *elem in (NSArray *)self.target) {
			[result addObject:[elem.presto toJSONObjectWithTemplate:arraySubTemplate]];
		}
		return [NSArray arrayWithArray:result]; // immutable
	} else
		return [self toDictionaryWithTemplate:template];
}

- (NSDictionary *)toDictionary {
	return [self toDictionaryWithTemplate:nil];
}

- (NSDictionary *)toDictionaryWithTemplate:(id)template {
	__strong NSObject *strongTarget = self.weakTarget;
	if (!strongTarget)
		return nil;
	if ([self.target isKindOfClass:[NSDictionary class]])
		return self.target; // we're already a dictionary! this avoids attempting to serialize NSDictionary's properties
	
	NSMutableArray* properties = [NSMutableArray new];
	Class class = [strongTarget class];
	
	while (class && class != [NSObject class]) {
		uint count;
		objc_property_t* c_properties = class_copyPropertyList(class, &count);
		for (int i = 0; i < count; i++)
			[properties addObject:[NSValue valueWithBytes:&c_properties[i] objCType:@encode(objc_property_t)]]; // TODO: do we need to free this ever? documentation isn't clear
		free(c_properties);
		class = [class superclass];
	}
	
	NSMutableDictionary* dictionary = [NSMutableDictionary dictionaryWithCapacity:properties.count];
	NSArray *serializationKeys;
	if (template) {
		if ([template isKindOfClass:[NSDictionary class]])
			serializationKeys = [template allKeys];
		else if ([template isKindOfClass:[NSArray class]])
			serializationKeys = template;
	}
//	if ([self.target respondsToSelector:@selector(serializingKeys)])
//		serializationKeys = [[self.target serializingKeys] mutableCopy];
	
	for (NSValue* value in properties) {
		objc_property_t c_property;
		[value getValue:&c_property];
		NSString* propertyName = [NSString stringWithCString:property_getName(c_property) encoding:NSUTF8StringEncoding];
		if ([propertyName isEqualToString:@"presto"])
			continue;
		NSString* fieldName = [self.manager fieldNameForProperty:propertyName forClass:[strongTarget class]];//self.targetClass];
		if (serializationKeys && ![serializationKeys containsObject:fieldName]) {
			if (LOG_VERBOSE)
				NSLog(@"Presto: Skipping property “%@” as it's not in serializationKeys.", propertyName);
			continue;
		}
		
		Class protocolClass;
		NSString* typeString = [NSString stringWithUTF8String:property_getAttributes(c_property)];
		// FIXME: this is horrible! ugh!
		NSString* propertiesString = [typeString substringWithRange:NSMakeRange([typeString rangeOfString:@","].location, [typeString rangeOfString:@"," options:NSBackwardsSearch].location - [typeString rangeOfString:@","].location)];
		if ([propertiesString containsString:@"W"]) {
			if (LOG_VERBOSE)
				NSLog(@"Presto: Skipping weak property “%@” (%@).", propertyName, typeString);
			continue;
		}
		if ([propertiesString containsString:@"R"]) {
			if (LOG_VERBOSE)
				NSLog(@"Presto: Skipping read-only property “%@” (%@).", propertyName, typeString);
			continue;
		}
		NSString* typeAttribute = [typeString componentsSeparatedByString:@","][0];
		NSString* typeName = @"";
		if (typeAttribute.length >= 4)
			typeName = [typeAttribute substringWithRange:NSMakeRange(3, [typeAttribute length] - 4)];
		NSString* propertyType = [typeAttribute substringFromIndex:1];
		long protocolIndex = [typeName rangeOfString:@"<"].location; // 0 if typeName is nil
		if (protocolIndex != 0 && protocolIndex != NSNotFound) {
			NSString* protocolName = [typeName substringWithRange:NSMakeRange(protocolIndex + 1, [typeName rangeOfString:@">" options:NSBackwardsSearch].location - protocolIndex - 1)];
//			if ([protocolName containsString:@","])
//				NSLog(@"Protocol: %@", protocolName);
			NSArray* protocolNames = [protocolName componentsSeparatedByString:@"><"];
			if ([protocolNames containsObject:@"DoNotSerialize"])
				continue;
			NSString* protocolTypeName = protocolName;//[self typeNameForProtocolName:protocolName]; // TODO: reimplement
			protocolClass = NSClassFromString(protocolTypeName);
			if (protocolClass == nil && LOG_WARNINGS) {
				PRLog(@"pRESTo Warning: protocolClass not determinable from protocol name ‘%@’.", protocolName);
			}
			typeName = [typeName substringToIndex:protocolIndex];
		}
//		propertyClass = NSClassFromString(typeName);
		
//		NSLog(@"propertyName: %@ class: %@", propertyName, [self.target class]);//temp
//		Class testClass = NSClassFromString(NSStringFromClass([self.target class]));
		if (![self.manager shouldPropertyBeSerialized:propertyName forClass:self.targetClass])
			continue;
		
		BOOL isBool = strcmp([propertyType UTF8String], @encode(BOOL)) == 0;
		
		id value = [self.target valueForKey:propertyName];
		if (value == self.target)
			NSAssert(false, @"whoa wait a second");
		
		id subTemplate = [template isKindOfClass:[NSDictionary class]] ? template[fieldName] : nil;
		
		// convert BOOL into NSNumber so it is serialized as "true" or "false":
		if (isBool && [value respondsToSelector:@selector(isEqualToNumber:)]) {
//			NSLog(@"BOOL!!!!!!!!!!!!!!!!!! %@", value);
			if ([value isEqualToNumber:@(0)])
				value = @NO;
			else if ([value isEqualToNumber:@(1)])
				value = @YES;
//			value = value ? @YES : @NO;
		}
		
		if ([value isKindOfClass:[Presto class]] || [value isKindOfClass:[PrestoMetadata class]] || [value isKindOfClass:[PrestoSource class]])
			continue; // don't serialize internal objects
		
//		PRLog(@"Serializing property “%@” of %@.", fieldName, self.targetClass);
		
		if (value == nil || value == [NSNull null])
			[dictionary setObject:[NSNull null] forKey:fieldName];
		else if ([NSJSONSerialization isValidJSONObject:@[value]]) { // the value has to be wrapped in something in order for isValidJSONObject to work properly; bizarre implementation --lmurray2015
			[dictionary setObject:value forKey:fieldName];
		} else if ([value isKindOfClass:[NSArray class]]) {
			NSMutableArray *arrayValue = [NSMutableArray arrayWithCapacity:((NSArray *)value).count];
			
			id arraySubTemplate;
			if ([subTemplate isKindOfClass:[NSArray class]]) {
				if ([subTemplate count])
					arraySubTemplate = subTemplate[0];
				else {
					arraySubTemplate = nil; // verify
//					if (LOG_WARNINGS)
//						PRLog(@"pRESTo Warning: Array template for embedded array should have exactly one child template object (NSArray or NSDictionary).");
				}
			}
			for (NSObject *object in (NSArray *)value) {
				[arrayValue addObject:[object.presto toDictionaryWithTemplate:arraySubTemplate]];
			}
			[dictionary setObject:arrayValue forKey:fieldName];
		} else {
//			NSLog(@"value: %@ key: %@", value, fieldName);
//			[dictionary setObject:value forKey:fieldName];
			[dictionary setObject:[[(NSObject *)value presto] toDictionaryWithTemplate:subTemplate] forKey:fieldName];
		}
		
//		[serializationKeys removeObject:fieldName];


	}
//	free(properties);
	
	// add null values for any missing keys
	for (NSString* key in serializationKeys) {
		if ([dictionary objectForKey:key] == nil)
			[dictionary setObject:[NSNull null] forKey:key];
	}
	
	return dictionary;
}

#pragma mark -

- (PrestoMetadata *)onComplete:(PrestoCallback)completion {
	[self onComplete:completion failure:nil];
	return self;
}

- (PrestoMetadata *)onChange:(PrestoCallback)dependency {
	return [self onChange:dependency forLifetimeOf:nil];
}

- (PrestoMetadata *)onChange:(PrestoCallback)dependency forLifetimeOf:(id)target {
	// this allows for group changes @[obj1, obj2].onChange
	if ([self.targetClass isSubclassOfClass:[NSArray class]] && ![self.targetClass isSubclassOfClass:[NSMutableArray class]] && !self.source.url) {// && !self.arrayClass) {
		[self addSetDependency:dependency forLifetimeOf:target];
		return self;
	}

//	PrestoSource* source = [self sourceForProperty:property];
	PrestoDependencyRecord* rec = [PrestoDependencyRecord new];
	if (target) {
		rec.owner = target;
		rec.hasOwner = YES;
	}
	rec.success = dependency;
	[self.callbacks addObject:rec];
	
	// slight hack here: if we add a dependency and there are no sources at all, we should probably still call it (allows for manually controlling an object that may not necessarily be loaded from the server)
	// should we perhaps wrap the isLoaded check in an async block so as to decouple the check from the definition of the source
	// typically we always define the source first so perhaps this isn't a big deal, but for completeness we probably should
	if (self.isLoaded) // used to have && !isLoading, but i removed this to support changed flag
		dependency(self.target);
	else if (!self.isLoading) {
		dispatch_async(dispatch_get_main_queue(), ^{
			if (!self.isLoading && !self.isDeferred)
				[self reload];
			else if (self.isDeferred) {
				if (LOG_VERBOSE)
					PRLog(@"Presto Notice: Deferring load of %@", self.source.url.absoluteString)
			}
		});
	}
	
	return self;
}

- (PrestoMetadata *)onComplete:(PrestoCallback)success failure:(PrestoCallback)failure {
	// if this is called on an immutable array, we assume it is an array of presto objects because immutable arrays can't be loaded dynamically
	if (self.targetClass == NSClassFromString(@"__NSArrayI") && ![self.targetClass isSubclassOfClass:[NSMutableArray class]] && !self.source.url) {// && !self.arrayClass) {
		[self addSetCompletion:success failure:failure];
		return self;
	}
	
//	PrestoSource* source = [self sourceForProperty:property];
	if (self.isLoaded && !self.isLoading) {
		if (success)
			success(self.target); // would there be any benefit in wrapping this in an async?
	} else {
		PrestoCompletionRecord* rec = [PrestoCompletionRecord new];
		rec.target = self.weakTarget; // completions keep the target alive and are guaranteed to fire (in theory)
		rec.success = success;
		rec.failure = failure;
//		[self.manager.globalCompletions addObject:rec];
		[self.callbacks addObject:rec];
		
		if (!self.isLoading) {
			dispatch_async(dispatch_get_main_queue(), ^{
				if (!self.isLoading && !self.isDeferred) // TODO: do we want to defer completions as well? or just dependencies?
					[self reload];
				else if (self.isDeferred) {
					if (LOG_VERBOSE)
						PRLog(@"Presto Notice: Deferring load of %@", self.source.url.absoluteString)
				}
			});
		}
	}
	return self;
}

// TODO: verify that this does not leak memory by keeping arbitrary arrays around indefinitely.
- (void)addSetCompletion:(PrestoCallback)success failure:(PrestoCallback)failure {
	NSArray *arrayTarget = (NSArray *)self.target; // should this be __block??
	
	// there might be a better way to do this
	// if this object has its own source/definition, treat it like a normal Presto object
	// this method is for subscribing to multiple dependencies at once for a completion or group dependency.
//	if (objc_getAssociatedObject(self, @selector(presto)) && self.presto.source.url) {
//		[self.presto addCompletion:success];
//		return;
//	}

	// this implementation assumes that an object cannot go from a loaded state to a non-loaded state
//	__block id strongSelf = self; // this used to be weak but it didn't work (array needs to be kept alive until its members complete)
	// TODO: the above may not be needed now that completions keep strong references
	__block NSDate* timestamp = [NSDate date];
	
//	PRLog(@"Attaching ARRAY completion at timestamp: %f", [timestamp timeIntervalSinceReferenceDate]);
	
	PrestoCallback interceptor = ^(NSObject *_){
//		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!arrayTarget) { // is this even possible anymore?
//			PRLog(@"Array completion strongSelf has disappeared! Did this array already complete??");
			return; // the array no longer exists; abort
		}
		
		BOOL allLoaded = YES;
		
		for (NSObject *elem in arrayTarget) {
			if (!elem.presto.isCompleted || [elem.presto loadingSince:timestamp]) {
				if (LOG_VERBOSE)
					PRLog(@"Array element %@ %@ failed completion check. array timestamp: %f", elem.presto, elem, [timestamp timeIntervalSinceReferenceDate]);
				allLoaded = NO;
				break;
			}
		}
		
		if (allLoaded) {
//			PRLog(@"Array completed. Calling success and setting strongSelf to nil.");
			BOOL allSucceeded = YES;
			for (NSObject *elem in arrayTarget) {
				if (elem.presto.error) {
					allSucceeded = NO;
					break;
				}
			}
			if (allSucceeded || !failure) {
				if (success)
					success(arrayTarget);
			} else {
				if (failure)
					failure(arrayTarget);
			}
//			arrayTarget = nil; // this was above success() does it need to be?
		}
	};
	
	for (NSObject *elem in self.target) {
//		if (![elem isKindOfClass:[RemoteObject class]])
//			continue; // see above
		
		[elem.presto onComplete:interceptor];
	}
}

- (void)addSetDependency:(PrestoCallback)dependency forLifetimeOf:(id)target {
	// TODO: is this really all we have to do here?
	for (NSObject *elem in self.target) {
		[elem.presto onChange:dependency forLifetimeOf:target];
	}
}

 // we definitely need a better way to do this
- (PrestoMetadata *)clearDependencies {
	for (PrestoCallbackRecord *callback in [self.callbacks copy]) {
		if ([callback isKindOfClass:[PrestoDependencyRecord class]])
			[self.callbacks removeObject:callback];
	}
	return self;
}

#pragma mark -

- (void)callSuccessBlocks:(BOOL)changed {// includeCompletions:(BOOL)includeCompletions {
//	if (!self.isLoaded)
//		return;
	
//	PRLog(@"Calling success blocks for %@\nCallbacks: %d Dependencies: %d", self, self.callbacks.count, self.dependencies.count);
	
	// this is weird like this because a callback can result in modifications to the callbacks array; so we need to do it in waves like this
	// hopefully this won't result in an infinite loop
	
	// TODO: do we still need to wrap this in a loop? what if we copy the array and clear it before calling any callbacks--will additional callbacks registered within another handler still be called?
	
	// TODO: we need to check the timestamp of a callback against the timestamp of the request
	// we need to figure out these timing issues so that we never have a "stalled" callback
	// this seems to be especially true for array callbacks
	__weak __block typeof(self) weakSelf = self;
	NSArray *callbacks = [self.callbacks copy];
	
	__block id target = self.target; // verify: does this create a retain cycle?
	
	// experimental: it makes sense to me that dependencies be considered higher priority than completions, as completions only execute once, it makes sense that they execute *after* the dependencies, but i'm not sure this makes sense
	// it may be a better idea to simply call these in whatever order they are registered in, and to not have two separate collections of dependencies vs. completions, but rather a flag to indicate which type each record is
	
	self.source.error = nil;
	
	// note: we may need to account for callbacks added as the result of calling another callback
	// however, it's possible that we should make this the reseponsibility of the add call. that is, if the object is in the state that it is currently calling callbacks, any new callback added during this time should also be called immediately?
	
	for (PrestoCallbackRecord *callback in callbacks) {
		if ([callback isKindOfClass:[PrestoCompletionRecord class]]) {
//			if (includeCompletions) {
				PrestoCompletionRecord *completion = (PrestoCompletionRecord *)callback;
				// FIXME: make sure this dispatch is enabled for release!
				if (completion.success) { // it's possible we may have a failure-only callback
					dispatch_async(dispatch_get_main_queue(), ^{
	//					__strong typeof(weakSelf) strongSelf = weakSelf;
	//					completion.success(strongSelf.target);
							completion.success(target); // is this safe?
					});
				}
				[self.callbacks removeObject:completion];
//			}
		} else if (changed && [callback isKindOfClass:[PrestoDependencyRecord class]]) {
			PrestoDependencyRecord *dependency = (PrestoDependencyRecord *)callback;
			__strong id owner = dependency.owner;
			if (owner || !dependency.hasOwner) {
				if (dependency.success) { // i don't think this is a concern, but just being careful
					dispatch_async(dispatch_get_main_queue(), ^{
						__strong typeof(weakSelf) strongSelf = weakSelf;
						dependency.success(strongSelf.target);
					});
				}
			} else if (dependency.hasOwner) {
				if (LOG_VERBOSE)
					PRLog(@"Dependency’s lifetime target has disappeared. Removing dependency.");
				[self.callbacks removeObject:dependency];
			}
		}
	}
}

- (void)callFailureBlocks:(BOOL)changed {
//	PRLog(@"Calling failure blocks for %@\nCallbacks: %d Dependencies: %d", self, self.callbacks.count, self.dependencies.count);

	__weak __block typeof(self) weakSelf = self;
	NSArray *callbacks = [self.callbacks copy];
	
	for (PrestoCallbackRecord *callback in callbacks) {
		if ([callback isKindOfClass:[PrestoCompletionRecord class]]) {
			dispatch_async(dispatch_get_main_queue(), ^{
				__strong typeof(weakSelf) strongSelf = weakSelf;
				if (callback.failure)
					callback.failure(strongSelf.target);
				else if (callback.success)
					callback.success(strongSelf.target);
			});
			[self.callbacks removeObject:callback];
		} else if ([callback isKindOfClass:[PrestoDependencyRecord class]]) {
			if (callback.failure) { // we only call explicit failure blocks on dependencies
				dispatch_async(dispatch_get_main_queue(), ^{
					__strong typeof(weakSelf) strongSelf = weakSelf;
					callback.failure(strongSelf.target);
				});
			}
		}
	}
}

#pragma mark -

// decouples the receiver from its current host. this does not invalidate the metadata. you can access its .target property to recreate a new host on the fly.
- (void)uninstall {
	__strong id strongTarget = self.weakTarget;
	
	if (!strongTarget)
		return; // no target; nothing to uninstall
	
	objc_setAssociatedObject(strongTarget, @selector(presto), nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

#pragma mark -

- (NSString *)description {
	// other cool symbols: 🔄⚠⛔◽🔳🔲✅☐☒☑
	NSString *typeName = [NSString stringWithFormat:@"%@@%d", self.targetClass, self.classDepth];
	NSString *statusIcon = self.error ? @"⛔" : (self.isLoaded ? @"✅" : (self.weakTarget ? @"🔲" : @"◽"));
	return [NSString stringWithFormat:@"%@%@ %@ 0x%x %@ %@", self.isLoading ? @"⌛" : @"", statusIcon, typeName, (uint)self.weakTarget, self.source.method, self.source.url.absoluteString];
}

@end

#pragma mark - NSObject (PrestoMetadata)

@implementation NSObject (PrestoMetadata)

- (PrestoMetadata *)presto {
	if ([self isKindOfClass:[PrestoMetadata class]])
		return (id)self; // experimental. allows calling .presto without worry
	
	if (objc_getAssociatedObject(self, @selector(presto)) == nil)
		[self installMetadata];
	
	return objc_getAssociatedObject(self, @selector(presto));
}

- (void)installMetadata {
	if ([self isKindOfClass:[PrestoMetadata class]])
		NSAssert(![self isKindOfClass:[PrestoMetadata class]], @"Presto! metadata cannot be installed recursively upon itself. This is probably an indication something else is wrong somewhere. Set a breakpoint here and trace back.");
//	if (LOG_VERBOSE)
//		PRLog(@"Installing Presto metadata on %@ %x", [self class], (uint)self);
	objc_setAssociatedObject(self, @selector(presto), [PrestoMetadata new], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	self.presto.weakTarget = self; // weak reference
}

// this could potentially break shit--do we really need this?
- (id)valueForUndefinedKey:(NSString *)key {
	return ValueForUndefinedKey; // a special object that indicates the runtime was not able to find a property with the requested key on the current object
}

@end

#undef PRLog
