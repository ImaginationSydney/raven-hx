package raven.types;

/**
 * ...
 * @author Thomas Byrne
 */
typedef RavenCall = {
	
	url:String,
	auth:RavenAuthData,
	data: RavenCallData,
	?attempts: Int,
	?options: RavenConfig,
	onSuccess:String->Void,
	onError:String->Void
	
}