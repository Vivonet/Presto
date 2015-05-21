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

#import "NSObject+Presto.h"

#pragma mark - NSObject (Presto)

// these are proxies on NSObject to the same methods on the underlying PrestoMetadata class
// if you don't want any of these proxies, you can just comment them out here and access them explicitly through the .presto property of any object
// similarly, feel free to add additional proxies you would like

@implementation NSObject (Presto)

#pragma mark - Properties

- (BOOL)isLoading {
	return self.presto.isLoading;
}

- (BOOL)isLoaded {
	return self.presto.isLoaded;
}

#pragma mark -

- (PrestoMetadata *)getFromURL:(NSURL *)url {
	return [self.presto getFromURL:url];
}

- (PrestoMetadata *)putToURL:(NSURL *)url {
	return [self.presto putToURL:url];
}

- (PrestoMetadata *)postToURL:(NSURL *)url {
	return [self.presto postToURL:url];
}

- (PrestoMetadata *)deleteFromURL:(NSURL *)url {
	return [self.presto deleteFromURL:url];
}

- (void)loadWithJSONString:(NSString *)json {
	[self.presto loadWithJSONString:json];
}

- (BOOL)loadWithDictionary:(NSDictionary *)dictionary {
	return [self.presto loadWithDictionary:dictionary];
}

#pragma mark -

- (NSString *)toJSONString {
	return [self.presto toJSONString];
}

- (NSDictionary *)toDictionary {
	return [self.presto toDictionary]; // does this work? i.e. unambiguously identify the correct method? or does it infinitely create nested metadata? we could add a private "hasMetadata" check if need be.
}

#pragma mark -

- (PrestoMetadata *)onComplete:(PrestoCallback)completion {
	return [self.presto onComplete:completion];
}

- (PrestoMetadata *)onComplete:(PrestoCallback)success failure:(PrestoCallback)failure {
	return [self.presto onComplete:success failure:failure];
}

- (PrestoMetadata *)onChange:(PrestoCallback)dependency {
	return [self.presto onChange:dependency];
}

- (PrestoMetadata *)onChange:(PrestoCallback)dependency withTarget:(id)target {
	return [self.presto onChange:dependency withTarget:target];
}

@end
