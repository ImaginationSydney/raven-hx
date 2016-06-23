package raven;
import haxe.Http;
import haxe.Json;
import raven.types.*;

using Reflect;
using StringTools;

/**
 * ...
 * @author Thomas Byrne
 */
class Raven
{
	private static var VERSION = '0.1';
	
	private static var DSN_KEYS = ['source', 'protocol', 'user', 'pass', 'host', 'port', 'path'];
	private static var DSN_PATTERN:EReg = ~/^(?:(\w+):)?\/\/(?:(\w+)(:\w+)?@)?([\w\.-]+)(?::(\d+))?(\/.*)/;

	private static var debug = true;
	private static var globalOptions:RavenConfig;
	
	private static var ignoreErrors:EReg;
	private static var ignoreUrls:EReg;
	private static var whitelistUrls:EReg;
	private static var includePaths:EReg;
	
	public static var	globalUser:RavenUser;
	
	private static var	lastCapturedException;
	private static var	lastEventId;
	private static var	globalServer;
	private static var	globalKey;
	private static var	globalProject;
	private static var startTime;
	
	
	/*
	 * Configure Raven with a DSN and extra options
	 *
	 * @param {string} dsn The public Sentry DSN
	 * @param {object} options Optional set of of global options [optional]
	 */
	 public static function config(dsn:String, ?options:RavenConfig) {
		/*if (globalServer!=null) {
			logDebug('error', 'Error: Raven has already been configured');
		}*/
		
		globalOptions = {
			logger: 'haxe',
			ignoreErrors: [],
			ignoreUrls: [],
			whitelistUrls: [],
			includePaths: [],
			crossOrigin: 'anonymous',
			maxMessageLength: 100
		};
		startTime = now();

		var uri:RavenDsn = parseDSN(dsn);
		var lastSlash = uri.path.lastIndexOf('/');
		var path = uri.path.substr(1, lastSlash);

		// merge in options
		if (options != null) {
			for (field in options.fields()) {
				globalOptions.setField(field, options.field(field));
			}
		}

		// "Script error." is hard coded into browsers for errors that it can't read.
		// this is the result of a script being pulled in from an external domain and CORS.
		globalOptions.ignoreErrors.push("^Script error\\.?$");
		globalOptions.ignoreErrors.push("^Javascript error: Script error\\.? on line 0$");

		// join regexp rules into one big rule
		ignoreErrors = joinRegExp(globalOptions.ignoreErrors);
		ignoreUrls = globalOptions.ignoreUrls.length>0 ? joinRegExp(globalOptions.ignoreUrls) : null;
		whitelistUrls = globalOptions.whitelistUrls.length>0 ? joinRegExp(globalOptions.whitelistUrls) : null;
		includePaths = joinRegExp(globalOptions.includePaths);

		globalKey = uri.user;
		globalProject = uri.path.substr(lastSlash + 1);

		// assemble the endpoint from the uri pieces
		globalServer = '//' + uri.host +
					  (uri.port!=null ? ':' + uri.port : '') +
					  '/' + path + 'api/' + globalProject + '/store/';

		if (uri.protocol!=null) {
			globalServer = uri.protocol + ':' + globalServer;
		}
	}
	
	private static var STACK_PATTERN:EReg = ~/\t*at ([_\d\w\.]+)::([_\d\w]+\$?)\/([_\d\w]+)\(\)\[(.+):(\d+)\]/;
	/*
	 * Manually capture an exception and send it over to Sentry
	 *
	 * @param {error} ex An exception to be logged
	 * @param {object} options A specific set of options for this error [optional]
	 * @return {Raven}
	 */
	 public static function captureException(errName:String, errMsg:String, url:String, stack:String, lineno:Int, ?options:RavenCallData) {
		var frames = [];

		if (stack != null && stack.length > 0) {
			var stackSplit = stack.split("\n");
			for (line in stackSplit) {
				if (STACK_PATTERN.match(line)) {
					var frame = {
						filename : STACK_PATTERN.matched(4),
						lineno : Std.parseInt(STACK_PATTERN.matched(5)),
						colno : 0
					};
					frame.setField("function", STACK_PATTERN.matched(1) + "." + STACK_PATTERN.matched(2) + "." + STACK_PATTERN.matched(3)+"()");
					frames.push( frame );
					
				}
			}
			// Break down the stack string here and put it into the frames array
		}

		processException(
			errName,
			errMsg,
			url,
			lineno,
			frames,
			options
		);
	}
	
	

	private static function processException(type:String, message:String, fileurl:String, lineno:Int, frames:Array<RavenStackFrame>, options:RavenCallData) {
		var stacktrace = null;
		var i, fullMessage;

		if (ignoreErrors!=null && ignoreErrors.match(message)) return;

		message += '';
		message = truncate(message, globalOptions.maxMessageLength);

		fullMessage = type + ': ' + message;
		fullMessage = truncate(fullMessage, globalOptions.maxMessageLength);

		if (frames != null && frames.length > 0) {
			var frame:RavenStackFrame = frames[0];
			fileurl = (frame.filename!=null ? frame.filename : fileurl);
			// Sentry expects frames oldest to newest
			// and JS sends them as newest to oldest
			frames.reverse();
			stacktrace = {frames: frames};
		} else if (fileurl!=null) {
			stacktrace = {
				frames: [{
					filename: fileurl,
					lineno: lineno,
					colno: 0,
					in_app: true
				}]
			};
		}

		if (ignoreUrls!=null && ignoreUrls.match(fileurl)) return;
		if (whitelistUrls!=null && !whitelistUrls.match(fileurl)) return;

		// Fire away!
		send(
			objectMerge({
				// sentry.interfaces.Exception
				exception: {
					type: type,
					value: message
				},
				// sentry.interfaces.Stacktrace
				stacktrace: stacktrace,
				culprit: fileurl,
				message: fullMessage
			}, options)
		);
	}
	

	/*
	 * Manually send a message to Sentry
	 *
	 * @param {string} msg A plain message to be captured in Sentry
	 * @param {object} options A specific set of options for this message [optional]
	 * @return {Raven}
	 */
	 public static function captureMessage(msg:String, ?options:RavenCallData) {
		// config() automagically converts ignoreErrors from a list to a RegExp so we need to test for an
		// early call; we'll error on the side of logging anything called before configuration since it's
		// probably something you should see:
		if (ignoreErrors!=null && ignoreErrors.match(msg)) {
			return;
		}

		// Fire away!
		send(
			objectMerge({
				message: msg + ''  // Make sure it's actually a string
			}, options)
		);
	}

	/*
	 * Get the latest raw exception that was captured by Raven.
	 *
	 * @return {error}
	 */
	public static function lastException() {
		return lastCapturedException;
	}

	/*
	 * Determine if Raven is setup and ready to go.
	 *
	 * @return {boolean}
	 */
	public static function isSetup() {
		if (globalServer==null) {
			return false;
		}
		return true;
	}
	
	private static function now():Float {
		return Date.now().getTime();
	}	
	

	private static function parseDSN(str):RavenDsn {
		if(!DSN_PATTERN.match(str)){
			throw ('Invalid DSN: ' + str);
		}
		var dsn = new RavenDsn();
		var i = DSN_KEYS.length;

		try {
			while (i-- > 0) {
				var val:String = DSN_PATTERN.matched(i);
				if (val == null) val = "";
				dsn.setField(DSN_KEYS[i], val);
			}
		} catch(e:Dynamic) {
			throw ('Invalid DSN: ' + str);
		}

		if (dsn.pass!=null && dsn.pass.length>0)
			throw ('Do not specify your private key in the DSN!');

		return dsn;
	}
	

	private static function truncate(str:String, max:Int):String {
		return str.length <= max ? str : str.substr(0, max) + '\u2026';
	}

	private static function getHttpData():RavenHttp {
		return null;

		/*var http = {
			headers: [
				'User-Agent'=> navigator.userAgent
			]
		};

		http.url = document.location.href;

		if (document.referrer) {
			http.headers.Referer = document.referrer;
		}

		return http;*/
	}

	private static function send(data:RavenCallData) {
		var baseData:RavenCallData = {
			project: globalProject,
			logger: globalOptions.logger,
			platform: 'haxe'
		};
		var http = getHttpData();
		if (http!=null) {
			baseData.request = http;
		}

		// Why??????????
		if (data==null || isEmptyObject(data)) {
			return;
		}

		data = objectMerge(baseData, data);

		// Merge in the tags and extra separately since objectMerge doesn't handle a deep merge
		var tags = objectMerge(globalOptions.tags, data.tags);
		if (tags != null) data.tags = tags;
		data.extra = objectMerge(globalOptions.extra, data.extra);

		// Send along our own collected metadata with extra
		data.extra = mapMerge([
			'session:duration'=> Std.string(now() - startTime)
		], data.extra);

		if (globalUser!=null) {
			// sentry.interfaces.User
			data.user = globalUser;
		}

		// Include the release if it's defined in globalOptions
		if (globalOptions.release!=null) data.release = globalOptions.release;

		if (globalOptions.dataCallback != null) {
			data = globalOptions.dataCallback(data);
		}

		// Check if the request should be filtered or not
		if (globalOptions.shouldSendCallback!=null && !globalOptions.shouldSendCallback(data)) {
			return;
		}

		// Send along an event_id if not explicitly passed.
		// This event_id can be used to reference the error within Sentry itself.
		// Set lastEventId after we know the error should actually be sent
		lastEventId = (data.event_id!=null ? data.event_id : (data.event_id = uuid4()));

		//logDebug('debug', 'Raven about to send:', data);

		if (!isSetup()) return;
		
		var looseData:Dynamic = data;
		
		if(looseData.tags!=null)looseData.tags = mapToObj(looseData.tags);
		if(looseData.extra!=null)looseData.extra = mapToObj(looseData.extra);
		
		var transport:RavenCall->Void = (globalOptions.transport!=null ? globalOptions.transport : makeRequest);

		transport({
			url: globalServer,
			auth: {
				sentry_version: '4',
				sentry_client: 'raven-hx/' + Raven.VERSION,
				sentry_key: globalKey,
				sentry_data:null
			},
			data: data,
			attempts:3,
			//options: globalOptions,
			
			onSuccess: function(res:String) {
			},
			onError: function(err:String) {
				//trace("Sentry tracking error: "+err);
			}
		});
	}
	
	static private function mapToObj(map:Map<String, Dynamic>):Dynamic
	{
		var ret = { };
		for (key in map.keys()) {
			ret.setField(key, map.get(key));
		}
		return ret;
	}
	
	static private function mapMerge(map1:Map<String, String>, map2:Map<String, String>) :Map<String, String>
	{
		if (map1 == null) return map2;
		if (map2 == null) return map1;
		
		for (key in map2.keys()) {
			map1.set(key, map2.get(key));
		}
		
		return map1;
	}
	
	static private function isEmptyObject(obj:Dynamic):Bool 
	{
		return obj.fields().length == 0;
	}

	private static function makeRequest(opts:RavenCall) {
		// Tack on sentry_data to auth options, which get urlencoded
		opts.auth.sentry_data = Json.stringify(opts.data);
		
		var src = opts.url + '?' + urlencode(opts.auth);
		var http = new Http(src);
		http.onData = opts.onSuccess;
		http.onError = requestError.bind(_, opts);
		http.request(false);

	}
	
	static private function requestError(err:String, opts:RavenCall) 
	{
		if (opts.attempts == null || opts.attempts <= 1) {
			opts.onError(err);
		}else {
			opts.attempts--;
			makeRequest(opts);
		}
	}
	


	private static function joinRegExp(patterns:Array<String>):EReg {
		// Combine an array of regular expressions and strings into one large regexp
		// Be mad.
		var sources = [],
			i = 0, len = patterns.length,
			pattern;

		while(i < len) {
			pattern = patterns[i];
			if (pattern == null) continue;
			/*if (Std.is(pattern, String)) {
				// If it's a string, we need to escape it
				// Taken from: https://developer.mozilla.org/en-US/docs/Web/JavaScript/Guide/Regular_Expressions
				pattern = (~/([.*+?^=!:${}()|\[\]\/\\])/g).replace(pattern, "\\$1");
				sources.push(pattern);
			} else if (pattern && pattern.source) {*/
				// If it's a regexp already, we want to extract the source
				sources.push(pattern);
			//}
			// Intentionally skip other cases
			i++;
		}
		return new EReg(sources.join('|'), 'i');
	}

	private static function uuid4() {
		return (~/[xy]/g).map('xxxxxxxxxxxx4xxxyxxxxxxxxxxxxxxx', function(reg:EReg) {
			var c = reg.matched(0);
			var r = Std.int(Math.random() * 16) | 0;
			var v = c == 'x' ? r : (r & 0x3 | 0x8);
			return v.hex();
		});
	}

	/*private static function logDebug(level) {
		if (originalConsoleMethods[level] && Raven.debug) {
			// _slice is coming from vendor/TraceKit/tracekit.js
			// so it's accessible globally
			originalConsoleMethods[level].apply(originalConsole, _slice.call(arguments, 1));
		}
	}*/

	private static function urlencode(o:Dynamic) {
		var pairs = [];
		for (field in o.fields()) {
			var value:String = o.field(field);
			pairs.push(field.urlEncode() + '=' + value.urlEncode());
		}
		return pairs.join('&');
	}
	
	private static function objectMerge<A>(obj1:A, obj2:Dynamic):A {
		if (obj2==null) {
			return obj1;
		}
		if (obj1==null) {
			return null;
		}
		for (field in obj2.fields()) {
			var val:Dynamic = obj2.field(field);
			if(val!=null)obj1.setField(field, val);
		}
		return obj1;
	}
	
}

