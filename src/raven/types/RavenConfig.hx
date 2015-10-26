package raven.types;

/**
 * ...
 * @author Thomas Byrne
 */
typedef RavenConfig =
{
	logger:String,
	crossOrigin:String,
	?release:String,
	maxMessageLength:Int,
	
	ignoreErrors:Array<String>,
	ignoreUrls:Array<String>,
	whitelistUrls:Array<String>,
	includePaths:Array<String>,
	
	?tags:Map<String, String>,
	?extra:Map<String, String>,
	
	?dataCallback:RavenCallData->RavenCallData,
	?shouldSendCallback:RavenCallData->Bool,
	?transport:Dynamic->Void
	
}