package ufront.web.client;

#if js
	import ufront.web.context.HttpContext;
	import js.Browser.window;
	import haxe.PosInfos;
	import haxe.extern.Rest;
#end

/**
UFClientAction is a Javascript action that will run on the client's web browser.

### Use cases for Client Actions.

Examples of what actions are appropriate for:

- Initialising some Javascript UI on page load.
- Setting up client-side form validation.
- Having an action run every 30 seconds to check for new notifications to show the user.

Examples of what actions are inappropriate for:

- Rendering an entire page. We recommend using a normal request / response cycle for this, so that if a client has Javascript disabled the page is still usable.
- Anything which should affect the browser's history state. If the user would expect the back button to undo your action, you should probably use a request / response cycle instead.

### Triggering client actions.

Actions can be triggered during a server request or from the client, even from 3rd party code.

See `AddClientActionResult.triggerAction()` for how to trigger actions from a HTTP request.
See `ClientJsApplication.executeAction()` for how to trigger actions on the client.

### Instantiation

The following process describes how actions are registered and executed on the client:

- Actions are registered with `ClientJsApplication.registerAction()`.
  This maps the action to the client application's injector as a singleton.
  (All actions in `UfrontClientConfiguration.clientActions` are registered when the app starts).
- When `ClientJsApplication.executeAction()` is called:
	- We use the application injector to fetch the singleton for the action.
	  This means it'll be created with dependency injection, and the same action instance will be re-used each time the action is triggered.
	- We will call `action.execute( ClientJsApplication.currentContext, data )`.

### Macro transformations.

A build macro is applied to all classes that extend `UFClientAction`.
This removes every field from the class on the server.
This is so that the class can exist on the server (so you can trigger client-side actions), while writing client specific code without conditional compilation.
**/
@:autoBuild( ufront.web.client.ClientActionMacros.emptyServer() )
class UFClientAction<T> {
	#if client
		/**
		Execute the current action with the given data.
		**/
		public function execute( context:HttpContext, ?data:Null<T> ):Void {}

		/**
		A default toString() that prints the current class name.
		This is useful primarily for logging requests and knowing which controller was called.
		**/
		@:noCompletion
		public function toString() {
			return Type.getClassName( Type.getClass(this) );
		}

		/**
		A shortcut to `console.log()`.
		Please note this will bypass the usual log handlers and print straight to the JS console.
		**/
		@:noCompletion
		inline function ufTrace( msg:Dynamic, ?pos:PosInfos ) logToConsole( window.console.log, msg, pos );

		/**
		A shortcut to `context.info()`.
		Please note this will bypass the usual log handlers and print straight to the JS console.
		**/
		@:noCompletion
		inline function ufLog( msg:Dynamic, ?pos:PosInfos ) logToConsole( window.console.info, msg, pos );

		/**
		A shortcut to `context.warn()`.
		Please note this will bypass the usual log handlers and print straight to the JS console.
		**/
		@:noCompletion
		inline function ufWarn( msg:Dynamic, ?pos:PosInfos ) logToConsole( window.console.warn, msg, pos );

		/**
		A shortcut to `context.error()`.
		Please note this will bypass the usual log handlers and print straight to the JS console.
		**/
		@:noCompletion
		inline function ufError( msg:Dynamic, ?pos:PosInfos ) logToConsole( window.console.error, msg, pos );

		inline function logToConsole( fn:Rest<Dynamic>->Void, msg:Dynamic, p:PosInfos ) {
			fn( '${p.className}.${p.methodName}()[${p.lineNumber}]:', msg );
		}
	#end
}
