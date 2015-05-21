# Presto!
A non-intrusive Objective-C REST framework that just works like magic!

♫ “If I could wave my magic wand…” ♫
https://youtu.be/iwIdXJPXpMU

## What is Presto?
Presto is an iOS REST bridge that eliminates much of the tedium of communicating with a remote REST source in a way that is already immediately intuitive to developers, without actually abstracting or obfuscating the REST interface itself. Presto simply reduces the time and steps needed to do what you already want to do, removing the mundane and time-wasting work of handling things like communication, serialization and change handling, and ties your remotely hosted JSON data directly to native objects via the Objective-C runtime. Presto is designed to non-intrusively tie itself into your existing data model and can automatically load your existing class objects with data from a remote source with minimal setup and a very easy learning curve.

For example, loading an object with a remote JSON definition is as simple as this:

	@interface MyProfile : NSObject
	
	@property (strong, nonatomic) NSString *name;
	@property (strong, nonatomic) NSString *email;
	@property (strong, nonatomic) int age;
	
	@end
	…
	self.profile = [MyProfile new];
	[self.profile getFromURL:url];

That's it! Provided your remote document looks something like this:

	{
		"name":"Logan",
		"email":"logan@example.com",
		"age":33,
	}

You can now attach completions and/or dependencies to self.profile and access the loaded properties from within the attached block.

Note that MyProfile inherits from NSObject, not some Presto class. With Presto you can load objects of *any* class, not just those that derive from a specific base class.

Presto’s aim is to make loading and manipulating remote data as simple as possible and does so by interacting with the Objective-C runtime to dynamically match server-side JSON attributes to client-side Objective-C properties.

Presto is also very fault-tolerant. If the library encounters a property or attribute it does not recognize, or a situation it doesn’t know how to handle, it will print a warning to the console, but otherwise continue without cause for alarm. This means your client and server side model don’t need to match exactly, nor do either of them need to be exhaustively defined. If your server returns information your client doesn’t need, you can safely just ignore it when using Presto.

Presto is a work in progress and is not yet in a state where it can be considered complete enough to handle all scenarios, but it is already quite capable enough to handle a large majority of requests. My hope is that as it develops, it will become more and more general purpose. In the meantime, if you see a feature or ability lacking in Presto that you would like to see implemented, please shoot me a line or open an issue for it. Or of course you can implement it yourself. I’ve tried to keep the code as simple and straightforward as possible to facilitate modifications.

Presto has a few core strengths and design goals:

0. It is designed to be as unobtrusive as possible. This means a couple things: First, it is very easy to integrate into your existing projects. There’s no need to change your model class definitions aside from possibly adding a few empty protocols and optional overrides. Secondly, it means you can gradually migrate code to Presto from your existing infrastructure a piece at a time. You can use Presto when and where you like, and leave legacy code intact. Presto is designed to make your life easier, not get in the way.
0. It has a powerful chained syntax. Aside from the necessary ugliness of a few extra square brackets in your code, Presto has a very powerful and expressive syntax that lets you stack on exactly the pieces you want, without the need for bloated and complicated method signatures. With Presto, `nil` parameters are a rarity.
0. It is designed to be as automatic as possbile, loading only what is needed when it is needed. With Presto you just code and go.
0. Presto should make your coding more intuitive and less bug-prone. With proper use of completions and depenencies, your app will also behave consistently and react automatically to remote changes.
0. In-place loading means you can refresh your objects from their server definitions without blowing away other local data. Working on a single instance of an object means more predictable behavior and instant compatibility with a wide range of existing designs.

## Disclaimer
This project is in its infancy and is constantly changing. Expect breaking changes. You’re more than welcome to depend on Presto in your projects, but for now you should link against a specific build and be aware that updating Presto may break your existing code. I will try to keep a changelog of all breaking changes introduced from version to version to facilitate new version adoption.

## Installation
Presto is contained for the most part in a single pair of files: Presto.h/m. There is also a handy (but optional) NSObject+Presto.h/m category which exposes Presto methods on NSObject. This category is designed to allow for easy customization and selection of the methods that suit your project. You can expose as many or as few of these category methods as you like.

To install Presto, just copy Presto.h/m into your project and import it where necessary. It is recommended that you #import the optional NSObject+Presto.h in your project’s precompiled header (.pch) file to make accessing Presto on any object automatic from anywhere in your project.

## The Basics
Presto works by attaching a non-intrusive "presto" metadata property dynamically onto any object that accesses it. Presto makes this property available on every NSObject in your code and lazy-loads itself the first time it is accessed. Presto uses the metadata to remember things about the object’s remote source, including its URL, HTTP method, request body, and generic request and response transformers.

You typically start by declaring an object’s remote location with one of four methods:
- getFromURL:
- putToURL:
- postToURL:
- deleteFromURL:

Each of these accepts an NSURL and returns a copy of the **PrestoMetadata** object that is created and attached to the host object, allowing you to chain additional configuration calls together.

For example, to modify the headers in the request sent to the server, you need only attach a transformer via the **withRequestTransformer:** method:

	[[self.profile getFromURL:url] withRequestTransformer:^(NSMutableURLRequest *request) {
		[request setValue:myUserAgent forHTTPHeaderField:@"User-Agent"];
	}];

(You can also attach global request and response transformers for your app via the **addGlobalRequestTransformer:** and **addGlobalResponseTransformer:** Presto class methods.)

You can call these methods on any object (so long as the NSObject+Presto category is included and imported, or upon the extended "presto" property of any object if not). You can also call **getFromURL:** and **deleteFromURL:** on the Presto class itself, in which case a new instance will be created based on the type information provided by either the **objectOfClass:** or **arrayOfClass:** method:

	MyClass* instance = [[[Presto getFromURL:url] objectOfClass:[MyClass class]];

The **objectOfClass:** and **arrayOfClass:** methods, unlike the other configuration methods, return a reference to the host object itself (rather than a PrestoMetadata object), instantiating one on the fly if it doesn’t yet exist. This allows you to easily define your class properties in a single line. Presto metadata objects can create their own host objects if needed, or can be attached to existing instances just as easily.

## Lazy Loading
Pretty much everything in Presto is lazy-loaded on the fly only when it is observed. Simply defining the source of an object does not immediately result in a call to the server. This only happens when you attach a completion or dependency to an object, which are the two ways in which Presto objects should be observed.

	self.myProfile = [[Presto getFromURL:url] objectOfClass:[MyProfile class]];
	// self.myProfile.name is nil here because we haven’t yet loaded the object
	[self.myProfile onComplete:^(NSObject* result) {
		// self.myProfile.name is now filled in because we are inside a completion block
	}];

## Completions
A completion allows you to decouple the code that handles a remote object from the code that loads it. You attach a completion to an object via the **onComplete:** method. A completion will only be called once after it is attached, but is guaranteed to be called eventually, whatever the result of the server call may be, including failure. If an object is already loaded, the completion will be executed immediately and the object will not be reloaded. If you want to force a refresh of the object, use **loadWithCompletion:** or simply call **load** before attaching the completion (which is exactly what loadWithCompletion: does).

## Dependencies
If you want a block of code to be called every time an object changes, use a dependency instead, by instead passing the same block to **onChange:**. You can also pass an optional weak target to **onChange:** that will existentially tie the given block to the existence of the target. If the target disappears, the block will no longer be called. Typically the current view or view controller is passed as this parameter, because if the view disappears, there's probably nothing to update anyway.

## What Doesn’t Presto Do?
As I've mentioned, Presto is still in its infancy. There are still some features and abilities that are planned or being considered that are not yet part of the framework. One such obvious omission is that of converters. There is no layer of conversion happening between a payload and your local properties.

For example, if your payload represents a date as a string or long, you'll need to convert these manually for now. The best place to do this is by adding a second local property of the desired type (e.g. NSDate) and adding a setter (or overriding setValue:forKey:) in your model class to set the converted value of the date property whenever the original property is set.

This is definitely one area I plan on improving soon, so hopefully we won't be stuck doing this for too much longer.

* * *

Like the rest of the project, this readme is a work in progress. More to come, including a demo project.