package ufront.web.mvc;
                       
import ufront.web.mvc.MvcRouteHandler;
import ufront.web.routing.Route;
import ufront.web.routing.RouteData;
import ufront.web.HttpContextMock;
import thx.error.Error;
import ufront.web.routing.RequestContext;
import utest.Runner;
import utest.ui.Report;

class TestAll
{
	public static function addTests(runner : Runner)
	{                                                  
		TestController.addTests(runner);
		TestDefaultControllerFactory.addTests(runner); 
		TestViewResult.addTests(runner);
	}
	
	public static function main()
	{
		var runner = new Runner();
		addTests(runner);
		Report.create(runner);
		runner.run();
	}     
	
	public static function getRequestContext()
	{
		var routeHandler = new MvcRouteHandler();
		var route = new Route("/", routeHandler);
		var context = new HttpContextMock();
		var routeData = new RouteData(route, routeHandler, new Hash());
		return new RequestContext(context, routeData, null);
	}
}