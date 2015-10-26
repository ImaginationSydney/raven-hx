package raven.types;

/**
 * @author Thomas Byrne
 */

typedef RavenStackFrame =
{
	filename:String,
	lineno:Int,
	colno:Int,
	?func:String,
	?in_app:Bool
}