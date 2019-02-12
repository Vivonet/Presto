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
//  Designed and coded by Logan Murray

#import <Foundation/Foundation.h>
#import "Presto.h"

// This class is completely optional. It simply exposes convenience methods on NSObject that proxy the same methods on the underlying PrestoMetadata instance. Feel free to add, remove or rename any methods in this class to suit the needs of your own project. -Logan

@interface NSObject (Presto)

/**
	Returns `YES` if the object is currently waiting on a load request to the server.
	
	It doesn’t matter if the object has already been loaded in the past or not.
*/
@property (nonatomic, readonly) BOOL isLoading;
/**
	Returns `YES` if the object has been successfully loaded at some point in the past. It does not necessarily reflect the status of the latest request.
*/
@property (nonatomic, readonly) BOOL isLoaded;

/**
	Loads the current object with the data returned from the requested URL.
	
	Returns the current object’s metadata record which can be used for chaining calls.
*/
- (PrestoMetadata *)getFromURL:(NSURL *)url;
/** Creates (or identifies*) a metadata object that represents the response of sending the current object as the payload of a `PUT` request to the given URL.

	You can chain multiple calls together to provide additional information to the request and generally end the chain with either `objectOfClass:` or `arrayOfClass:` to cast the response to the appropriate response class.
	
	*Note: If the response class implements an `identifyingKey` method, Presto will use that identifying key to look up and return any existing instance, after loading it with the information returned in the response.
*/
- (PrestoMetadata *)putToURL:(NSURL *)url;
/** Creates (or identifies*) a metadata object that represents the response of sending the current object as the payload of a `POST` request to the given URL.

	You can chain multiple calls together to provide additional information to the request and generally end the chain with either `objectOfClass:` or `arrayOfClass:` to cast the response to the appropriate class.
	
	*Note: If the response class implements an `identifyingKey` method, Presto will use that identifying key to look up and return any existing instance, after loading it with the information returned in the response.
*/
- (PrestoMetadata *)postToURL:(NSURL *)url;
/** Creates (or identifies*) a metadata object that represents the response of sending the current object as the payload of a `DELETE` request to the given URL.

	You can chain multiple calls together to provide additional information to the request and generally end the chain with either `objectOfClass:` or `arrayOfClass:` to cast the response to the appropriate class.
	
	*Note: If the response class implements an `identifyingKey` method, Presto will use that identifying key to look up and return any existing instance, after loading it with the information returned in the response.
*/
- (PrestoMetadata *)deleteFromURL:(NSURL *)url;

/**
	Loads the current object with the data represented by a JSON-encoded string, as if the server had returned that string from a load request.
*/
- (void)loadWithJSONString:(NSString *)json;
/**
	Loads the current object with the data represented in an `NSDictionary`.
*/
- (BOOL)loadWithDictionary:(NSDictionary *)dictionary;

- (NSString *)toJSONString;
- (NSDictionary *)toDictionary;

- (PrestoMetadata *)putSelf;
- (PrestoMetadata *)postSelf;

- (PrestoMetadata *)reload;
- (PrestoMetadata *)reloadIfOlderThan:(NSTimeInterval)age;
- (PrestoMetadata *)invalidate;

- (PrestoMetadata *)onComplete:(PrestoCallback)completion;
- (PrestoMetadata *)onComplete:(PrestoCallback)success failure:(PrestoCallback)failure;
- (PrestoMetadata *)onChange:(PrestoCallback)dependency;
- (PrestoMetadata *)onChange:(PrestoCallback)dependency forLifetimeOf:(id)target;

@end
