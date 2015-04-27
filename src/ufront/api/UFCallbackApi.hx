package ufront.api;

import haxe.EnumFlags;
import ufront.remoting.RemotingError;
import haxe.CallStack;
import ufront.remoting.RemotingUtil;
import haxe.rtti.Meta;
using tink.CoreApi;

/**
An asynchronous proxy that calls a server API, using callbacks to wait for the result.

#### Transformation:

Each public method of the `UFApi` you are proxying will be available in the proxy.
Instead of returning a value though, each method will contain two callbacks:

- An `onResult:T->Void` callback, to process a succesful request.
- An optional `onError:T->Void` callback, to process a failed request.

#### Callback typing:

The `onResult` and `onError` callbacks for each function will be typed as follows:

- A return type of `:Surprise<A,B>` will create a callback of `A->Void`, and an error callback of `RemotingError<B>->Void`.
- A return type of `:Future<T>` will create a callback of `T->Void`, and an error callback of `RemotingError<Noise>->Void`.
- A return type of `:Outcome<A,B>` will create a callback of `A->Void`, and an error callback of `RemotingError<B>->Void`.
- A return type of `:Void` will create a callback of `Noise->Void`, and an error callback of `RemotingError<Noise>->Void`.
- A return type of `:T` will create a callback of `T->Void`, and an error callback of `RemotingError<Noise>->Void`.

Each callback is typed as `tink.core.Callback`, so both `T->Void` and `Void->Void` callbacks are accepted.

#### Client and Server differences:

On the client it uses an injected `AsyncConnection` to perform the remoting call.

On the server, the original API will be called, and the result will be passed to our callbacks.
If the server API is synchronous, the callbacks will also be called synchronously.

Using the same Async Callback methods allows identical usage of the API on both the client or the server.

#### Injections:

The class must have the following injected to be functional:

- On the server, `api` - an instance of the original API object.
- On the client, `cnx` - an `AsyncConnection` to use for remoting.
- Both will be injected if you are using ufront's `Injector`.

#### Integration with UFApiContext:

If a `UFApiClientContext` is generated, it will automatically create a `UFCallbackApi` for each `UFApi` in the `UFApiContext`.
This allows you to quickly generate a single class controlling all remoting access to your client.

#### UFCallbackApi and UFAsyncApi:

This class is quite similar to `UFAsyncApi`, except it uses callbacks rather than returning a `Surprise`.
If your client code is using Ufront, it will probably be easier to use `UFAsyncApi` and call them from your controllers on the client or server.
If your client code is not using Ufront, or particularly if it is not written in Haxe, it may be easier to create a `UFClientApiContext` and use the callback style APIs.

#### Usage:

```haxe
class AsyncLoginApi extends UFCallbackApi<LoginApi> {}

var api = new AsyncLoginApi();
api.attemptLogin( username, password, function(user:User) {
  trace( 'You are logged in as $user!');
}, function(err:RemotingError<Dynamic>) {
  trace( 'Error while logging in: $err' );
});
```

#### Trivia:

Extending this class produces an almost identical result to extending `haxe.remoting.AsyncProxy`.
However, `AsyncProxy` is documented as "magic", using internal compiler code rather than readable code or macros in the standard library.
This makes it hard to reason about, and impossible to customise.
The motivation to re-implement it using macros came for 2 reasons:

1. To handle the case of APIs that return a `Future` or a `Surprise`.
2. To avoid creating the `Async${apiName}` class that is auto-generated by Haxe, which was causing naming conflicts in some Ufront projects.
**/
#if !macro
@:autoBuild( ufront.api.ApiMacros.buildCallbackApiProxy() )
#end
class UFCallbackApi<SyncApi:UFApi> {
	var className:String;
	#if server
		/**
		Because of limitations between minject and generics, we cannot simply use `@inject public var api:T` based on a type paremeter.
		Instead, we get the build macro to create a `@inject public function injectApi( injector:Injector )` method, specifying the class of our sync Api as a constant.
		**/
		public var api:SyncApi;
		public function new() {}
	#elseif client
		public var cnx:haxe.remoting.AsyncConnection;

		// Because the client side may often be used outside of ufront, we should make it easy to inject the cnx from the constructor, without using minject.
		@inject public function new(cnx) {
			this.cnx = cnx;
		}
	#end


	function _makeApiCall<A,B>( method:String, args:Array<Dynamic>, flags:EnumFlags<ApiReturnType>, onResult:Callback<A>, ?onError:Callback<RemotingError<B>> ):Void {
		if ( className==null )
			className = Type.getClassName( Type.getClass(this) );
		var remotingCallString = '$className.$method(${args.join(",")})';
		#if server
			function callApi():Dynamic {
				return Reflect.callMethod( api, Reflect.field(api,method), args );
			}
			function processError( e:Dynamic ) {
				var stack = CallStack.toString( CallStack.exceptionStack() );
				onError.invoke( ServerSideException(remotingCallString,e,stack) );
			}
			if ( onError==null ) {
				onError = function(err) {};
			}

			if ( flags.has(ARTVoid) ) {
				try {
					callApi();
					onResult.invoke( null );
				}
				catch ( e:Dynamic ) processError(e);
			}
			else if ( flags.has(ARTFuture) && flags.has(ARTOutcome) ) {
				try {
					var surprise:Surprise<A,B> = callApi();
					surprise.handle(function(result) switch result {
						case Success(data): onResult.invoke( data );
						case Failure(err): onError.invoke( ApiFailure(remotingCallString,err) );
					});
				}
				catch ( e:Dynamic ) processError(e);
			}
			else if ( flags.has(ARTFuture) ) {
				try {
					var future:Future<A> = callApi();
					future.handle(function(data) {
						onResult.invoke( data );
					});
				}
				catch ( e:Dynamic ) processError(e);
			}
			else if ( flags.has(ARTOutcome) ) {
				try {
					var outcome:Outcome<A,B> = callApi();
					switch outcome {
						case Success(data): onResult.invoke( data );
						case Failure(err): onError.invoke( ApiFailure(remotingCallString,err) );
					}
				}
				catch ( e:Dynamic ) processError(e);
			}
			else {
				try {
					var result:A = callApi();
					onResult.invoke( result );
				}
				catch ( e:Dynamic ) processError(e);
			}
		#elseif client
			var cnx = cnx.resolve(className).resolve(method);
			if ( onError!=null ) {
				// We can't use `bind` on `cb.invoke` for setErrorHandler, because it's Abstract / Inline.
				var errHandler = function (e:RemotingError<B>) onError.invoke( e );
				cnx.setErrorHandler( errHandler );
			}
			cnx.call( args, function(result:Dynamic) {
				if ( flags.has(ARTVoid) ) {
					onResult.invoke( null );
				}
				else if ( flags.has(ARTOutcome) ) {
					var outcome:Outcome<A,B> = result;
					switch outcome {
						case Success(data): onResult.invoke( data );
						case Failure(err): onError.invoke( ApiFailure(remotingCallString,err) );
					}
				}
				else {
					onResult.invoke( result );
				}
			});
		#end
	}

	/**
	For a given sync `UFApi` class, see if a matching `UFCallbackApi` class is available, and return it.

	Returns null if no matching `UFCallbackApi` was found.

	This works by looking for `@callbackApi("path.to.AsyncCallbackApi")` metadata on the given `syncApi` class.
	This metadata should be generated by `UFCallbackApi`'s build macro.
	**/
	public static function getCallbackApi<T:UFApi>( syncApi:Class<T> ):Null<Class<UFCallbackApi<T>>> {
		var meta = Meta.getType(syncApi);
		if ( meta.callbackApi!=null ) {
			var asyncCallbackApiName:String = meta.callbackApi[0];
			if ( asyncCallbackApiName!=null ) {
				return cast Type.resolveClass( asyncCallbackApiName );
			}
		}
		return null;
	}
}
