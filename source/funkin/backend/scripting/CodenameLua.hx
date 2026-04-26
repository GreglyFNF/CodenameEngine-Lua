package funkin.backend.scripting;

//Flixel
import flixel.sound.FlxSound;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxCamera;
import flixel.math.FlxMath;
import flixel.math.FlxPoint;
import flixel.util.FlxColor;
import flixel.util.FlxTimer;
import flixel.text.FlxText;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.group.FlxSpriteGroup;
import flixel.group.FlxGroup.FlxTypedGroup;

import funkin.backend.utils.CoolUtil;
import funkin.backend.utils.TranslationUtil as TU;

import lime.utils.AssetLibrary;
import openfl.utils.Assets as OpenFlAssets;
import animate.FlxAnimateFrames;
import lime.utils.Assets;

import haxe.Constraints.Function;

#if sys
import sys.FileSystem;
#end
import sys.io.File;
import haxe.io.Path;


// coding from scratch i am going to die

#if LUA_ALLOWED

import funkin.backend.scripting.lua.*;
import llua.Convert;

class CodenameLua extends Script {
	public var lua:State = null;
	public var camTarget:FlxCamera;
	public var scriptName:String = '';
	public var modFolder:String = null;
	public var closed:Bool = false;

	public var code:String = null;

	#if HSCRIPT_ALLOWED
	public var hscript:HScript = null;
	#end

	public var callbacks:Map<String, Dynamic> = [];

	public static var customFunctions:Map<String, Dynamic> = [];

	public override function onCreate(path:String) {
		super.onCreate(path);

		lua = LuaL.newstate();
		LuaL.openlibs(lua);

		Lua.set_callbacks_function(cpp.Callable.fromStaticFunction(funkin.backend.scripting.CodenameLua.CallbackHandler.call));

		this.path = path.trim();

		if(!path.endsWith("lua")) return;

		if (!FileSystem.exists(path)) return;
		var game:PlayState = PlayState.instance;
		if(game != null) game.luaArray.push(this);

		for(k=>e in Script.getDefaultVariables(this)) set(k, e);
		addLuaFunctions();

		for (name => func in customFunctions)
		{
			if(func != null)
				Lua_helper.add_callback(lua, name, func);
		}

		try{
			var isString:Bool = !FileSystem.exists(path);
			var result:Dynamic = null;
			if(!isString)
				result = LuaL.dofile(lua, path);
			else
				result = LuaL.dostring(lua, path);

			var resultStr:String = Lua.tostring(lua, result);
			if(resultStr != null && result != 0) {
				trace(resultStr);
				#if windows
				lime.app.Application.current.window.alert(resultStr, 'Error on lua script!');
				#else
				luaTrace('$path\n$resultStr', true, false, FlxColor.RED);
				#end
				lua = null;
				return;
			}
			if(isString) path = 'unknown';
		} catch(e:Dynamic) {
			trace(e);
			return;
		}
		trace('lua file loaded succesfully:' + path);
		load();
		call('onCreate', []);
	}

	//main
	public var lastCalledFunction:String = '';
	public static var lastCalledScript:CodenameLua = null;
	private override function onCall(func:String, args:Array<Dynamic>):Dynamic {
		if(closed) return LuaUtils.Function_Continue;

		lastCalledFunction = func;
		lastCalledScript = this;
		try {
			if(lua == null) return LuaUtils.Function_Continue;
			Convert.enableUnsupportedTraces = false;

			Lua.getglobal(lua, func);
			var type:Int = Lua.type(lua, -1);

			if (type != Lua.LUA_TFUNCTION) {
				if (type > Lua.LUA_TNIL)
					luaTrace("ERROR (" + func + "): attempt to call a " + LuaUtils.typeToString(type) + " value", false, false, FlxColor.RED);

				Lua.pop(lua, 1);
				return LuaUtils.Function_Continue;
			}

			for (arg in args) Convert.toLua(lua, arg);
			var status:Int = Lua.pcall(lua, args.length, 1, 0);
			//trace(status);

			// Checks if it's not successful, then show a error.
			if (status != Lua.LUA_OK) {
				var error:String = getErrorMessage(status);
				luaTrace("ERROR (" + func + "): " + error, false, false, FlxColor.RED);
				return LuaUtils.Function_Continue;
			}

			// If successful, pass and then return the result.
			var result:Dynamic = cast Convert.fromLua(lua, -1);
			//trace(result);
			if (result == null) result = LuaUtils.Function_Continue;

			Lua.pop(lua, 1);
			if(closed) stop();
			return result;
		}
		catch (e:Dynamic) {
			trace(e);
		}
		return LuaUtils.Function_Continue;
	}

	public function stop() {
		closed = true;

		if(lua == null) {
			return;
		}
		Lua.close(lua);
		lua = null;
		#if HSCRIPT_ALLOWED
		if(hscript != null)
		{
			hscript.destroy();
			hscript = null;
		}
		#end
	}

	public function addLocalCallback(name:String, myFunction:Dynamic)
	{
		callbacks.set(name, myFunction);
		Lua_helper.add_callback(lua, name, null); //just so that it gets called
	}

	inline private function addCallback(name:String, myFunction:Function):Void
		Lua_helper.add_callback(lua, name, myFunction);

	inline private function removeCallback(name:String):Void
		Lua_helper.remove_callback(lua, name);

	public override function set(variable:String, data:Dynamic) {
		if(lua == null) {
			return;
		}

		Convert.toLua(lua, data);
		Lua.setglobal(lua, variable);
	}
	public override function get(name:String):Dynamic {
		#if LUA_ALLOWED
		if (lua == null)
			return null;
		
		var result:Dynamic = null;
		Lua.getglobal(lua, name);
		result = Convert.fromLua(lua, -1);
		Lua.pop(lua, 1);
		return result;

		#else
		return null;
		#end
	}


	public override function trace(v:Dynamic) {
		Logs.traceColored([
			Logs.logText('${fileName}:line placeholder: ', GREEN),
			Logs.logText(Std.isOfType(v, String) ? v : Std.string(v))
		], TRACE);
	}

	public override function reload() {
		// save variables

		onCreate(path);

		for(k=>e in Script.getDefaultVariables(this))
			set(k, e);

		addLuaFunctions();

		trace("evil");

		load();
	}

	public function addLuaFunctions() {
		trace("evil");
		set('Function_StopLua', LuaUtils.Function_StopLua);
		set('Function_StopHScript', LuaUtils.Function_StopHScript);
		set('Function_StopAll', LuaUtils.Function_StopAll);
		set('Function_Stop', LuaUtils.Function_Stop);
		set('Function_Continue', LuaUtils.Function_Continue);
		set('luaDebugMode', false);
		set('luaDeprecatedWarnings', true);
		set('inChartEditor', false);

		//funkin.game.psychlua.FlxAnimateFunctions.implement(this);
		ReflectionFunctions.implement(this);
		TextFunctions.implement(this);
		ExtraFunctions.implement(this);
		CustomSubstate.implement(this);
		//ShaderFunctions.implement(this);
		DeprecatedFunctions.implement(this);

		addCallback("trace", function(name) this.trace(name));
		addCallback("debugPrint", function(text:Dynamic = '', color:String = 'WHITE') PlayState.instance.addTextToDebug(text, CoolUtil.colorFromString(color)));

		addLocalCallback("close", function() {
			closed = true;
			trace('Closing script $path');
			return closed;
		});
	}

	public static function luaTrace(text:String, ignoreCheck:Bool = false, deprecated:Bool = false, color:FlxColor = FlxColor.WHITE) {
		if(ignoreCheck || getBool('luaDebugMode')) {
			if(deprecated && !getBool('luaDeprecatedWarnings')) {
				return;
			}
			PlayState.instance.addTextToDebug(text, color);
		}
	}

	public static function getBool(variable:String) {
		if(lastCalledScript == null) return false;

		var lua:State = lastCalledScript.lua;
		if(lua == null) return false;

		var result:String = null;
		Lua.getglobal(lua, variable);
		result = Convert.fromLua(lua, -1);
		Lua.pop(lua, 1);

		if(result == null) {
			return false;
		}
		return (result == 'true');
	}

	function findScript(scriptFile:String, ext:String = '.lua')
	{
		if(!scriptFile.endsWith(ext)) scriptFile += ext;
		var path:String = Paths.getPath(scriptFile);
		#if MODS_ALLOWED
		if(FileSystem.exists(path))
		#else
		if(Assets.exists(path))
		#end
		{
			return path;
		}
		#if MODS_ALLOWED
		else if(FileSystem.exists(scriptFile))
		#else
		else if(Assets.exists(scriptFile))
		#end
		{
			return scriptFile;
		}
		return null;
	}

	public function getErrorMessage(status:Int):String {
		var v:String = Lua.tostring(lua, -1);
		Lua.pop(lua, 1);

		if (v != null) v = v.trim();
		if (v == null || v == "") {
			switch(status) {
				case Lua.LUA_ERRRUN: return "Runtime Error";
				case Lua.LUA_ERRMEM: return "Memory Allocation Error";
				case Lua.LUA_ERRERR: return "Critical Error";
			}
			return "Unknown Error";
		}

		return v;
		return null;
	}

}

class CallbackHandler
{
	public static inline function call(l:State, fname:String):Int
	{
		try
		{
			trace('calling $fname');
			var cbf:Dynamic = Lua_helper.callbacks.get(fname);

			//Local functions have the lowest priority
			//This is to prevent a "for" loop being called in every single operation,
			//so that it only loops on reserved/special functions
			if(cbf == null) 
			{
				trace('checking last script');
				var last:CodenameLua = CodenameLua.lastCalledScript;
				if(last == null || last.lua != l)
				{
					trace('looping thru scripts');
					for (script in PlayState.instance.luaArray)
						if(script != CodenameLua.lastCalledScript && script != null && script.lua == l)
						{
							trace('found script');
							cbf = script.callbacks.get(fname);
							break;
						}
				}
				else cbf = last.callbacks.get(fname);
			}
			
			if(cbf == null) return 0;

			var nparams:Int = Lua.gettop(l);
			var args:Array<Dynamic> = [];

			for (i in 0...nparams) {
				args[i] = Convert.fromLua(l, i + 1);
			}

			var ret:Dynamic = null;
			/* return the number of results */

			ret = Reflect.callMethod(null,cbf,args);

			if(ret != null){
				Convert.toLua(l, ret);
				return 1;
			}
		}
		catch(e:haxe.Exception)
		{
			if(Lua_helper.sendErrorsToLua)
			{
				LuaL.error(l, 'CALLBACK ERROR! ${e.details()}');
				return 0;
			}
			throw e;
		}
		return 0;
	}
}
#end