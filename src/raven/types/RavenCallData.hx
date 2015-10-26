package raven.types;

/**
 * @author Thomas Byrne
 */

typedef RavenCallData =
{
	?project: String,
	?logger: String,
	?platform: String,
	?event_id: String,
	?request: RavenHttp,
	?release: String,
	
	?user: Map<String, String>,
	?tags:Map<String, String>,
	?extra:Map<String, String>,
	
	?exception: RavenException,
	?stacktrace: { frames : Array<RavenStackFrame>},
	?culprit:String,
	?message:String
	
}