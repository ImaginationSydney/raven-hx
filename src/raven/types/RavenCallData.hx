package raven.types;

/**
 * @author Thomas Byrne
 */

typedef RavenCallData =
{
	?level:Int,
	?project: String,
	?logger: String,
	?platform: String,
	?event_id: String,
	?request: RavenHttp,
	?release: String,
	
	?user: RavenUser,
	?tags:Map<String, String>,
	?extra:Map<String, String>,
	
	?exception: RavenException,
	?stacktrace: { frames : Array<RavenStackFrame>},
	?culprit:String,
	?message:String
	
}