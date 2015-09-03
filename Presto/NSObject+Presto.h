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

#import <Foundation/Foundation.h>
#import "Presto.h"

// This class is completely optional. It simply exposes convenience methods on NSObject that proxy the same methods on the underlying PrestoMetadata instance. Feel free to add, remove or rename any methods in this class to suit the needs of your own project. -Logan

@interface NSObject (Presto)

@property (nonatomic, readonly) BOOL isLoading;
@property (nonatomic, readonly) BOOL isLoaded;

- (PrestoMetadata *)getFromURL:(NSURL *)url;
- (PrestoMetadata *)putToURL:(NSURL *)url;
- (PrestoMetadata *)postToURL:(NSURL *)url;
- (PrestoMetadata *)deleteFromURL:(NSURL *)url;

- (void)loadWithJSONString:(NSString *)json;
- (BOOL)loadWithDictionary:(NSDictionary *)dictionary;

- (NSString *)toJSONString;
- (NSDictionary *)toDictionary;

- (PrestoMetadata *)putSelf;
- (PrestoMetadata *)postSelf;

- (PrestoMetadata *)reload;
- (PrestoMetadata *)invalidate;

- (PrestoMetadata *)onComplete:(PrestoCallback)completion;
- (PrestoMetadata *)onComplete:(PrestoCallback)success failure:(PrestoCallback)failure;
//
- (PrestoMetadata *)onChange:(PrestoCallback)dependency;
- (PrestoMetadata *)onChange:(PrestoCallback)dependency withTarget:(id)target;

@end
