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

import funkin.game.GameOverSubstate;
import flixel.addons.transition.FlxTransitionableState;
import funkin.menus.*;
import funkin.backend.system.Conductor;


// coding from scratch i am going to die

#if LUA_ALLOWED

import funkin.backend.scripting.lua.*;
import funkin.backend.scripting.lua.LuaUtils.LuaTweenOptions;
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

	var game:PlayState;

	public override function onCreate(path:String) {
		super.onCreate(path);

		lua = LuaL.newstate();
		LuaL.openlibs(lua);

		//Lua.set_callbacks_function(cpp.Callable.fromStaticFunction(funkin.backend.scripting.CodenameLua.CallbackHandler.call));
		Lua.init_callbacks(lua);

		this.path = path.trim();

		if(!path.endsWith("lua")) return;

		if (!FileSystem.exists(path)) return;
		game = PlayState.instance;
		if(game != null) game.luaArray.push(this);

		for(k=>e in Script.getDefaultVariables(this)) set(k, e);
		addLuaFunctions();

		for (name => func in customFunctions)
		{
			if(func != null)
				addCallback(name, func);
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
				throw resultStr;
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
	public static var lastCalledScript:CodenameLua = null;
	public override function call(func:String, ?parameters:Array<Dynamic>):Dynamic {
		#if LUA_ALLOWED
		if (lua==null) return LuaUtils.Function_Continue;
		
		try {
			var ret = executeFunc(func, parameters);
			return ret==null ? LuaUtils.Function_Continue : ret;
		}catch(e:Dynamic){
			trace(e);
		}
		#end

		return LuaUtils.Function_Continue;
	}
	private function executeFunc(name:String, ?args:Array<Dynamic>):Null<Dynamic>
	{
		lastCalledScript = this;

		if (args == null) args = [];
		Lua.getglobal(lua, name);
		#if (linc_luajit >= "0.0.6")
		if(Lua.isfunction(lua, -1)==true)
		#else
		if(Lua.isfunction(lua, -1)==1)
		#end
		{
			var result:Dynamic;
			if (args != null){
				for (arg in args) Convert.toLua(lua, arg);
				result = Lua.pcall(lua, args.length, 1, 0);
			}else{
				result = Lua.pcall(lua, 0, 1, 0);
			}

			if(result!=0){
				var err = getErrorMessage();

				var args = [for (arg in args){
					(arg is String ? '"$arg"' : Std.string(arg));
				}];
				trace(err);
				trace('$path: Error on function $name(${args.join(', ')}): $err');
				
				/* just so your output isnt SPAMMED
				if (!duplicateErrors.contains(err)) {
					var args = [for (arg in args){
						(arg is String ? '"$arg"' : Std.string(arg));
					}];
					Main.print('$scriptName: Error on function $func(${args.join(', ')}): $err');
					duplicateErrors.push(err);
					while(duplicateErrors.length > 20)
						duplicateErrors.shift();
				}*/

				return null;
			}else if(result != null){
				var conv:Dynamic = cast Convert.fromLua(lua, -1);
				Lua.pop(lua, 1);
				return conv;
			}
		}

		Lua.pop(lua, 1);
		return null;
	}

	public function stop():Void {
		#if LUA_ALLOWED
		if (lua == null)
			return;

		Lua.close(lua);
		lua = null;
		#end
	}

	public function oldTweenFunction(tag:String, vars:String, tweenValue:Any, duration:Float, ease:String, funcName:String)
	{
		var target:Dynamic = LuaUtils.tweenPrepare(tag, vars);
		var variables = MusicBeatState.getVariables();
		if(target != null)
		{
			if(tag != null)
			{
				var originalTag:String = tag;
				tag = LuaUtils.formatVariable('tween_$tag');
				variables.set(tag, FlxTween.tween(target, tweenValue, duration, {ease: LuaUtils.getTweenEaseByString(ease),
					onComplete: function(twn:FlxTween)
					{
						variables.remove(tag);
						if(PlayState.instance != null) PlayState.instance.callOnLuas('onTweenCompleted', [originalTag, vars]);
					}
				}));
			}
			else FlxTween.tween(target, tweenValue, duration, {ease: LuaUtils.getTweenEaseByString(ease)});
			return tag;
		}
		else luaTrace('$funcName: Couldnt find object: $vars', false, false, FlxColor.RED);
		return null;
	}

	public function addLocalCallback(name:String, myFunction:Dynamic)
	{
		callbacks.set(name, myFunction);
		Lua_helper.add_callback(lua, name, null); //just so that it gets called
	}

	inline public function addCallback(name:String, myFunction:Function):Void
		Lua_helper.add_callback(lua, name, myFunction);

	inline public function removeCallback(name:String):Void
		Lua_helper.remove_callback(lua, name);

	public override function set(name:String, val:Dynamic):Void
	{
		#if LUA_ALLOWED
		if (lua == null)
			return;

		//trace('${name}, ${val}');

		/** Convert.toLua(lua, val); **/
		switch (Type.typeof(val)) {
			case Type.ValueType.TNull:
				Lua.pushnil(lua);
			case Type.ValueType.TBool:
				Lua.pushboolean(lua, val);
			case Type.ValueType.TInt:
				Lua.pushinteger(lua, cast(val, Int));
			case Type.ValueType.TFloat:
				Lua.pushnumber(lua, val);
			case Type.ValueType.TClass(String):
				Lua.pushstring(lua, cast(val, String));
			case Type.ValueType.TClass(Array):
				Convert.arrayToLua(lua, val);
			case Type.ValueType.TObject:
				@:privateAccess Convert.anonToLua(lua, val); // {}
			case Type.ValueType.TFunction:
				addCallback(name, val);
				return;
			default:
				//trace('$path: Unsupported value: $val ${Type.typeof(val)}');
				return;
		}
		
		Lua.setglobal(lua, name);
		#end
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
		//trace("evil");
		set('Function_StopLua', LuaUtils.Function_StopLua);
		set('Function_StopHScript', LuaUtils.Function_StopHScript);
		set('Function_StopAll', LuaUtils.Function_StopAll);
		set('Function_Stop', LuaUtils.Function_Stop);
		set('Function_Continue', LuaUtils.Function_Continue);
		set('luaDebugMode', false);
		set('luaDeprecatedWarnings', true);
		set('inChartEditor', false);

		mainLuaVars();
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

	public function mainLuaVars(){
		/*
		// Song/Week shit
		set('curBpm', Conductor.bpm);
		set('bpm', PlayState.SONG.meta.bpm);
		set('scrollSpeed', PlayState.SONG.scrollSpeed);
		set('crochet', Conductor.crochet);
		set('stepCrochet', Conductor.stepCrochet);
		set('songLength', null);
		set('songName', PlayState.SONG.meta.name);
		//set('songPath', Paths.formatToSongPath(PlayState.SONG.song));
		set('startedCountdown', false);
		///set('curStage', game.curStage);

		set('isStoryMode', PlayState.isStoryMode);

		set('weekRaw', PlayState.storyWeek);
		//set('week', WeekData.weekList[PlayState.storyWeek]);
		set('seenCutscene', PlayState.seenCutscene);
		set('hasVocals', PlayState.SONG.meta.needsVoices);

		// Screen stuff
		set('screenWidth', FlxG.width);
		set('screenHeight', FlxG.height);


		// PlayState-only variables
		if(game != null)
		{
			//set('curSection', 0);
			set('curBeat', Conductor.curBeat);
			set('curStep', Conductor.curStep);
	
			set('score', PlayState.songScore);
			set('misses', PlayState.misses);
			set('hits', 0);
			set('combo', PlayState.combo);
			set('deaths', game.deathCounter);
	
			set('totalPlayed', 0);
			set('totalNotesHit', 0);

			set('inGameOver', GameOverSubstate.instance != null);

			set('healthGainMult', 1);
			set('healthLossMult', 1);
	
			set('playbackRate', 1);
	
			//set('instakillOnMiss', game.instakillOnMiss);
			//set('botPlay', ((game.player.cpu == true && !PlayState.opponentMode) || (game.cpu.cpu == true && PlayState.opponentMode)));
			set('practice', false);
	
			// Default character data
			set('defaultBoyfriendX', game.boyfriend.x);
			set('defaultBoyfriendY', game.boyfriend.y);
			set('defaultOpponentX', game.dad.x);
			set('defaultOpponentY', game.dad.y);
			set('defaultGirlfriendX', game.gf.x);
			set('defaultGirlfriendY', game.gf.y);

			set('boyfriendName', game.boyfriend != null ? game.boyfriend.curCharacter : PlayState.SONG.strumLines[1].characters[0]);
			set('dadName', game.dad != null ? game.dad.curCharacter : PlayState.SONG.strumLines[0].characters[0]);
			set('gfName', game.gf != null ? game.gf.curCharacter : PlayState.SONG.strumLines[2].characters[0]);
		}
			*/

		// Other settings
		//set('downscroll', game.downscroll);
		//set('ghostTapping', game.ghostTapping);
		//set('flashingLights', funkin.options.Options.flashingMenu);

		// build target (windows, mac, linux, etc.)
		//set('buildTarget', LuaUtils.getBuildTarget());

		//
		addCallback("getRunningScripts", function() {
			var runningScripts:Array<String> = [];
			for (script in game.luaArray)
				runningScripts.push(script.path);

			return runningScripts;
		});

		addCallback("callScript", function(luaFile:String, funcName:String, ?args:Array<Dynamic> = null) {
			if(args == null){
				args = [];
			}

			var luaPath:String = findScript(luaFile);
			if(luaPath != null)
				for (luaInstance in game.luaArray)
					if(luaInstance.path == luaPath)
						return luaInstance.call(funcName, args);

			return null;
		});
		addCallback("isRunning", function(scriptFile:String) {
			var luaPath:String = findScript(scriptFile);
			if(luaPath != null)
			{
				for (luaInstance in game.luaArray)
					if(luaInstance.path == luaPath)
						return true;
			}

			return false;
		});

		addCallback("removeVar", function(varName:String) {
			if(MusicBeatState.getVariables().exists(varName))
			{
				MusicBeatState.getVariables().remove(varName);
				return true;
			}
			return false;
		});

		addCallback("setVar", function(varName:String, value:Dynamic) {
			MusicBeatState.getVariables().set(varName, ReflectionFunctions.parseSingleInstance(value));
			return value;
		});
		addCallback("getVar", function(varName:String) {
			return MusicBeatState.getVariables().get(varName);
		});

		addCallback("addLuaScript", function(luaFile:String, ?ignoreAlreadyRunning:Bool = false) {
			var luaPath:String = findScript(luaFile);
			if(luaPath != null)
			{
				if(!ignoreAlreadyRunning)
					for (luaInstance in game.luaArray)
						if(luaInstance.path == luaPath)
						{
							luaTrace('addLuaScript: The script "' + luaPath + '" is already running!');
							return;
						}

				new CodenameLua(luaPath);
				return;
			}
			luaTrace("addLuaScript: Script doesn't exist!", false, false, FlxColor.RED);
		});
		addCallback("addHScript", function(scriptFile:String, ?ignoreAlreadyRunning:Bool = false) {
			luaTrace("addHScript: Lua HScript is not supported on this platform yet.", false, false, FlxColor.RED);
		});
		addCallback("removeLuaScript", function(luaFile:String) {
			var luaPath:String = findScript(luaFile);
			if(luaPath != null)
			{
				var foundAny:Bool = false;
				for (luaInstance in game.luaArray)
				{
					if(luaInstance.path == luaPath)
					{
						trace('Closing lua script $luaPath');
						luaInstance.stop();
						foundAny = true;
					}
				}
				if(foundAny) return true;
			}

			luaTrace('removeLuaScript: Script $luaFile isn\'t running!', false, false, FlxColor.RED);
			return false;
		});
		addCallback("removeHScript", function(scriptFile:String) {
			luaTrace("addHScript: Lua HScript is not supported on this platform yet.", false, false, FlxColor.RED);
		});

		addCallback("loadSong", function(?name:String = null, ?difficultyNum:String = null) {
			PlayState.loadSong(name, difficultyNum, '');
			FlxG.state.persistentUpdate = false;
			FlxG.switchState(new PlayState());

			FlxG.sound.music.pause();
			FlxG.sound.music.volume = 0;
			if(game != null && game.vocals != null)
			{
				game.vocals.pause();
				game.vocals.volume = 0;
			}
			FlxG.camera.followLerp = 0;
		});

		addCallback("loadGraphic", function(variable:String, image:String, ?gridX:Int = 0, ?gridY:Int = 0) {
			var split:Array<String> = variable.split('.');
			var spr:FlxSprite = LuaUtils.getObjectDirectly(split[0]);
			var animated = gridX != 0 || gridY != 0;

			if(split.length > 1) {
				spr = LuaUtils.getVarInArray(LuaUtils.getPropertyLoop(split), split[split.length-1]);
			}

			if(spr != null && image != null && image.length > 0)
			{
				spr.loadGraphic(Paths.image(image), animated, gridX, gridY);
			}
		});
		addCallback("loadFrames", function(variable:String, image:String, spriteType:String = 'auto') {
			var split:Array<String> = variable.split('.');
			var spr:FlxSprite = LuaUtils.getObjectDirectly(split[0]);
			if(split.length > 1) {
				spr = LuaUtils.getVarInArray(LuaUtils.getPropertyLoop(split), split[split.length-1]);
			}

			if(spr != null && image != null && image.length > 0)
			{
				LuaUtils.loadFrames(spr, image, spriteType);
			}
		});

		//shitass stuff for epic coders like me B)  *image of obama giving himself a medal*
		addCallback("getObjectOrder", function(obj:String, ?group:String = null) {
			var leObj:FlxBasic = LuaUtils.getObjectDirectly(obj);
			if(leObj != null)
			{
				if(group != null)
				{
					var groupOrArray:Dynamic = Reflect.getProperty(LuaUtils.getTargetInstance(), group);
					if(groupOrArray != null)
					{
						switch(Type.typeof(groupOrArray))
						{
							case TClass(Array): //Is Array
								return groupOrArray.indexOf(leObj);
							default: //Is Group
								return Reflect.getProperty(groupOrArray, 'members').indexOf(leObj); //Has to use a Reflect here because of FlxTypedSpriteGroup
						}
					}
					else
					{
						luaTrace('getObjectOrder: Group $group doesn\'t exist!', false, false, FlxColor.RED);
						return -1;
					}
				}
				var groupOrArray:Dynamic = CustomSubstate.instance != null ? CustomSubstate.instance : LuaUtils.getTargetInstance();
				return groupOrArray.members.indexOf(leObj);
			}
			luaTrace('getObjectOrder: Object $obj doesn\'t exist!', false, false, FlxColor.RED);
			return -1;
		});
		addCallback("setObjectOrder", function(obj:String, position:Int, ?group:String = null) {
			var leObj:FlxBasic = LuaUtils.getObjectDirectly(obj);
			if(leObj != null)
			{
				if(group != null)
				{
					var groupOrArray:Dynamic = Reflect.getProperty(LuaUtils.getTargetInstance(), group);
					if(groupOrArray != null)
					{
						switch(Type.typeof(groupOrArray))
						{
							case TClass(Array): //Is Array
								groupOrArray.remove(leObj);
								groupOrArray.insert(position, leObj);
							default: //Is Group
								groupOrArray.remove(leObj, true);
								groupOrArray.insert(position, leObj);
						}
					}
					else luaTrace('setObjectOrder: Group $group doesn\'t exist!', false, false, FlxColor.RED);
				}
				else
				{
					var groupOrArray:Dynamic = CustomSubstate.instance != null ? CustomSubstate.instance : LuaUtils.getTargetInstance();
					groupOrArray.remove(leObj, true);
					groupOrArray.insert(position, leObj);
				}
				return;
			}
			luaTrace('setObjectOrder: Object $obj doesn\'t exist!', false, false, FlxColor.RED);
		});

		// gay ass tweens
		addCallback("startTween", function(tag:String, vars:String, values:Any = null, duration:Float, ?options:Any = null) {
			var penisExam:Dynamic = LuaUtils.tweenPrepare(tag, vars);
			if(penisExam != null)
			{
				if(values != null)
				{
					var myOptions:LuaTweenOptions = LuaUtils.getLuaTween(options);
					if(tag != null)
					{
						var variables = MusicBeatState.getVariables();
						var originalTag:String = 'tween_' + LuaUtils.formatVariable(tag);
						variables.set(tag, FlxTween.tween(penisExam, values, duration, myOptions != null ? {
							type: myOptions.type,
							ease: myOptions.ease,
							startDelay: myOptions.startDelay,
							loopDelay: myOptions.loopDelay,
	
							onUpdate: function(twn:FlxTween) {
								if(myOptions.onUpdate != null) game.scripts.call(myOptions.onUpdate, [originalTag, vars]);
							},
							onStart: function(twn:FlxTween) {
								if(myOptions.onStart != null) game.scripts.call(myOptions.onStart, [originalTag, vars]);
							},
							onComplete: function(twn:FlxTween) {
								if(twn.type == FlxTweenType.ONESHOT || twn.type == FlxTweenType.BACKWARD) variables.remove(tag);
								if(myOptions.onComplete != null) game.scripts.call(myOptions.onComplete, [originalTag, vars]);
							}
						} : null));
						return tag;
					}
					else FlxTween.tween(penisExam, values, duration, myOptions != null ? {
						type: myOptions.type,
						ease: myOptions.ease,
						startDelay: myOptions.startDelay,
						loopDelay: myOptions.loopDelay,

						onUpdate: function(twn:FlxTween) {
							if(myOptions.onUpdate != null) game.scripts.call(myOptions.onUpdate, [null, vars]);
						},
						onStart: function(twn:FlxTween) {
							if(myOptions.onStart != null) game.scripts.call(myOptions.onStart, [null, vars]);
						},
						onComplete: function(twn:FlxTween) {
							if(myOptions.onComplete != null) game.scripts.call(myOptions.onComplete, [null, vars]);
						}
					} : null);
				}
				else luaTrace('startTween: No values on 2nd argument!', false, false, FlxColor.RED);
			}
			else luaTrace('startTween: Couldnt find object: ' + vars, false, false, FlxColor.RED);
			return null;
		});

		addCallback("doTweenX", function(tag:String, vars:String, value:Dynamic, duration:Float, ?ease:String = 'linear') {
			return oldTweenFunction(tag, vars, {x: value}, duration, ease, 'doTweenX');
		});
		addCallback("doTweenY", function(tag:String, vars:String, value:Dynamic, duration:Float, ?ease:String = 'linear') {
			return oldTweenFunction(tag, vars, {y: value}, duration, ease, 'doTweenY');
		});
		addCallback("doTweenAngle", function(tag:String, vars:String, value:Dynamic, duration:Float, ?ease:String = 'linear') {
			return oldTweenFunction(tag, vars, {angle: value}, duration, ease, 'doTweenAngle');
		});
		addCallback("doTweenAlpha", function(tag:String, vars:String, value:Dynamic, duration:Float, ?ease:String = 'linear') {
			return oldTweenFunction(tag, vars, {alpha: value}, duration, ease, 'doTweenAlpha');
		});
		addCallback("doTweenZoom", function(tag:String, camera:String, value:Dynamic, duration:Float, ?ease:String = 'linear') {
			switch(camera.toLowerCase()) {
				case 'camgame' | 'game': camera = 'camGame';
				case 'camhud' | 'hud': camera = 'camHUD';
				case 'camother' | 'other': camera = 'camOther';
				default:
					var cam:FlxCamera = MusicBeatState.getVariables().get(camera);
					if (cam == null || !Std.isOfType(cam, FlxCamera)) camera = 'camGame';
			}
			return oldTweenFunction(tag, camera, {zoom: value}, duration, ease, 'doTweenZoom');
		});
		addCallback("doTweenColor", function(tag:String, vars:String, targetColor:String, duration:Float, ?ease:String = 'linear') {
			var penisExam:Dynamic = LuaUtils.tweenPrepare(tag, vars);
			if(penisExam != null) {
				var curColor:FlxColor = penisExam.color;
				curColor.alphaFloat = penisExam.alpha;
				
				if(tag != null)
				{
					var originalTag:String = tag;
					tag = LuaUtils.formatVariable('tween_$tag');
					var variables = MusicBeatState.getVariables();
					variables.set(tag, FlxTween.color(penisExam, duration, curColor, CoolUtil.colorFromString(targetColor), {ease: LuaUtils.getTweenEaseByString(ease),
						onComplete: function(twn:FlxTween)
						{
							variables.remove(tag);
							if (game != null) game.scripts.call('onTweenCompleted', [originalTag, vars]);
						}
					}));
					return tag;
				}
				else FlxTween.color(penisExam, duration, curColor, CoolUtil.colorFromString(targetColor), {ease: LuaUtils.getTweenEaseByString(ease)});
			}
			else luaTrace('doTweenColor: Couldnt find object: ' + vars, false, false, FlxColor.RED);
			return null;
		});

		addCallback("mouseClicked", function(?button:String = 'left') {
			var click:Bool = FlxG.mouse.justPressed;
			switch(button.trim().toLowerCase())
			{
				case 'middle':
					click = FlxG.mouse.justPressedMiddle;
				case 'right':
					click = FlxG.mouse.justPressedRight;
			}
			return click;
		});
		addCallback("mousePressed", function(?button:String = 'left') {
			var press:Bool = FlxG.mouse.pressed;
			switch(button.trim().toLowerCase())
			{
				case 'middle':
					press = FlxG.mouse.pressedMiddle;
				case 'right':
					press = FlxG.mouse.pressedRight;
			}
			return press;
		});
		addCallback("mouseReleased", function(?button:String = 'left') {
			var released:Bool = FlxG.mouse.justReleased;
			switch(button.trim().toLowerCase())
			{
				case 'middle':
					released = FlxG.mouse.justReleasedMiddle;
				case 'right':
					released = FlxG.mouse.justReleasedRight;
			}
			return released;
		});

		addCallback("cancelTween", function(tag:String) LuaUtils.cancelTween(tag));

		addCallback("runTimer", function(tag:String, time:Float = 1, loops:Int = 1) {
			LuaUtils.cancelTimer(tag);
			var variables = MusicBeatState.getVariables();
			
			var originalTag:String = tag;
			tag = LuaUtils.formatVariable('timer_$tag');
			variables.set(tag, new FlxTimer().start(time, function(tmr:FlxTimer)
			{
				if(tmr.finished) variables.remove(tag);
				game.scripts.call('onTimerCompleted', [originalTag, tmr.loops, tmr.loopsLeft]);
				//trace('Timer Completed: ' + tag);
			}, loops));
			return tag;
		});
		addCallback("cancelTimer", function(tag:String) LuaUtils.cancelTimer(tag));

		//stupid bietch ass functions
		addCallback("addScore", function(value:Int = 0) {
			game.songScore += value;
		});
		addCallback("addMisses", function(value:Int = 0) {
			game.misses += value;
		});
		addCallback("setScore", function(value:Int = 0) {
			game.songScore = value;
		});
		addCallback("setMisses", function(value:Int = 0) {
			game.misses = value;
		});
		addCallback("setHealth", function(value:Float = 1) game.health = value);
		addCallback("addHealth", function(value:Float = 0) game.health += value);
		addCallback("getHealth", function() return game.health);

		//Identical functions
		addCallback("FlxColor", function(color:String) return FlxColor.fromString(color));
		addCallback("getColorFromName", function(color:String) return FlxColor.fromString(color));
		addCallback("getColorFromString", function(color:String) return FlxColor.fromString(color));
		addCallback("getColorFromHex", function(color:String) return FlxColor.fromString('#$color'));

		// precaching
		addCallback("addCharacterToList", function(name:String, type:String) {
			var charType:Int = 0;
			switch(type.toLowerCase()) {
				case 'dad': charType = 1;
				case 'gf' | 'girlfriend': charType = 2;
			}
			//game.addCharacterToList(name, charType);
		});
		addCallback("precacheImage", function(name:String, ?allowGPU:Bool = true) {
			Paths.image(name, allowGPU);
		});
		addCallback("precacheSound", function(name:String) {
			Paths.sound(name);
		});
		addCallback("precacheMusic", function(name:String) {
			Paths.music(name);
		});

		// others
		/*
		addCallback("triggerEvent", function(name:String, ?value1:String = '', ?value2:String = '') {
			game.triggerEventNote(name, value1, value2, Conductor.songPosition);
			//trace('Triggered event: ' + name + ', ' + value1 + ', ' + value2);
			return true;
		});*/

		addCallback("startCountdown", function() {
			game.startCountdown();
			return true;
		});
		addCallback("endSong", function() {
			//game.KillNotes();
			game.endSong();
			return true;
		});
		addCallback("restartSong", function(?skipTransition:Bool = false) {
			game.persistentUpdate = false;
			FlxG.camera.followLerp = 0;
			FlxG.resetState();
			return true;
		});
		addCallback("exitSong", function(?skipTransition:Bool = false) {
			if(skipTransition)
			{
				FlxTransitionableState.skipNextTransIn = true;
				FlxTransitionableState.skipNextTransOut = true;
			}

			if(PlayState.isStoryMode)
				FlxG.switchState(new StoryMenuState());
			else
				FlxG.switchState(new FreeplayState());

			//#if DISCORD_ALLOWED DiscordClient.resetClientID(); #end

			CoolUtil.playMenuSong();
			PlayState.chartingMode = false;
			//game.transitioning = true;
			FlxG.camera.followLerp = 0;
			//Mods.loadTopMod();
			return true;
		});
		addCallback("getSongPosition", function() {
			return Conductor.songPosition;
		});

		addCallback("getCharacterX", function(type:String) {
			switch(type.toLowerCase()) {
				case 'dad' | 'opponent':
					return game.dad.x;
				case 'gf' | 'girlfriend':
					return game.gf.x;
				default:
					return game.boyfriend.x;
			}
		});
		addCallback("setCharacterX", function(type:String, value:Float) {
			switch(type.toLowerCase()) {
				case 'dad' | 'opponent':
					game.dad.x = value;
				case 'gf' | 'girlfriend':
					game.gf.x = value;
				default:
					game.boyfriend.x = value;
			}
		});
		addCallback("getCharacterY", function(type:String) {
			switch(type.toLowerCase()) {
				case 'dad' | 'opponent':
					return game.dad.y;
				case 'gf' | 'girlfriend':
					return game.gf.y;
				default:
					return game.boyfriend.y;
			}
		});
		addCallback("setCharacterY", function(type:String, value:Float) {
			switch(type.toLowerCase()) {
				case 'dad' | 'opponent':
					game.dad.y = value;
				case 'gf' | 'girlfriend':
					game.gf.y = value;
				default:
					game.boyfriend.y = value;
			}
		});
		addCallback("cameraSetTarget", function(target:String) {
			switch(target.trim().toLowerCase())
			{
				case 'gf', 'girlfriend':
					game.curCameraTarget = 2;
					game.moveCamera();
				case 'dad', 'opponent':
					game.curCameraTarget = 0;
					game.moveCamera();
				default:
					game.curCameraTarget = 1;
					game.moveCamera();
			}
		});

		addCallback("setCameraScroll", function(x:Float, y:Float) FlxG.camera.scroll.set(x - FlxG.width/2, y - FlxG.height/2));
		addCallback("setCameraFollowPoint", function(x:Float, y:Float) game.camFollow.setPosition(x, y));
		addCallback("addCameraScroll", function(?x:Float = 0, ?y:Float = 0) FlxG.camera.scroll.add(x, y));
		addCallback("addCameraFollowPoint", function(?x:Float = 0, ?y:Float = 0) {
			game.camFollow.x += x;
			game.camFollow.y += y;
		});
		addCallback("getCameraScrollX", () -> FlxG.camera.scroll.x + FlxG.width/2);
		addCallback("getCameraScrollY", () -> FlxG.camera.scroll.y + FlxG.height/2);
		addCallback("getCameraFollowX", () -> game.camFollow.x);
		addCallback("getCameraFollowY", () -> game.camFollow.y);

		addCallback("cameraShake", function(camera:String, intensity:Float, duration:Float) {
			LuaUtils.cameraFromString(camera).shake(intensity, duration);
		});

		addCallback("cameraFlash", function(camera:String, color:String, duration:Float,forced:Bool) {
			LuaUtils.cameraFromString(camera).flash(CoolUtil.colorFromString(color), duration, null, forced);
		});
		addCallback("cameraFade", function(camera:String, color:String, duration:Float, forced:Bool, ?fadeOut:Bool = false) {
			LuaUtils.cameraFromString(camera).fade(CoolUtil.colorFromString(color), duration, fadeOut, null, forced);
		});
		//addCallback("updateScoreText", function() game.updateScoreText());
		addCallback("getMouseX", function(?camera:String = 'game') {
			var cam:FlxCamera = LuaUtils.cameraFromString(camera);
			return FlxG.mouse.getScreenPosition(cam).x;
		});
		addCallback("getMouseY", function(?camera:String = 'game') {
			var cam:FlxCamera = LuaUtils.cameraFromString(camera);
			return FlxG.mouse.getScreenPosition(cam).y;
		});

		addCallback("getMidpointX", function(variable:String) {
			var split:Array<String> = variable.split('.');
			var obj:FlxObject = LuaUtils.getObjectDirectly(split[0]);
			if(split.length > 1) {
				obj = LuaUtils.getVarInArray(LuaUtils.getPropertyLoop(split), split[split.length-1]);
			}
			if(obj != null) return obj.getMidpoint().x;

			return 0;
		});
		addCallback("getMidpointY", function(variable:String) {
			var split:Array<String> = variable.split('.');
			var obj:FlxObject = LuaUtils.getObjectDirectly(split[0]);
			if(split.length > 1) {
				obj = LuaUtils.getVarInArray(LuaUtils.getPropertyLoop(split), split[split.length-1]);
			}
			if(obj != null) return obj.getMidpoint().y;

			return 0;
		});
		addCallback("getGraphicMidpointX", function(variable:String) {
			var split:Array<String> = variable.split('.');
			var obj:FlxSprite = LuaUtils.getObjectDirectly(split[0]);
			if(split.length > 1) {
				obj = LuaUtils.getVarInArray(LuaUtils.getPropertyLoop(split), split[split.length-1]);
			}
			if(obj != null) return obj.getGraphicMidpoint().x;

			return 0;
		});
		addCallback("getGraphicMidpointY", function(variable:String) {
			var split:Array<String> = variable.split('.');
			var obj:FlxSprite = LuaUtils.getObjectDirectly(split[0]);
			if(split.length > 1) {
				obj = LuaUtils.getVarInArray(LuaUtils.getPropertyLoop(split), split[split.length-1]);
			}
			if(obj != null) return obj.getGraphicMidpoint().y;

			return 0;
		});
		addCallback("getScreenPositionX", function(variable:String, ?camera:String = 'game') {
			var split:Array<String> = variable.split('.');
			var obj:FlxObject = LuaUtils.getObjectDirectly(split[0]);
			if(split.length > 1) {
				obj = LuaUtils.getVarInArray(LuaUtils.getPropertyLoop(split), split[split.length-1]);
			}
			if(obj != null) return obj.getScreenPosition(LuaUtils.cameraFromString(camera)).x;

			return 0;
		});
		addCallback("getScreenPositionY", function(variable:String, ?camera:String = 'game') {
			var split:Array<String> = variable.split('.');
			var obj:FlxObject = LuaUtils.getObjectDirectly(split[0]);
			if(split.length > 1) {
				obj = LuaUtils.getVarInArray(LuaUtils.getPropertyLoop(split), split[split.length-1]);
			}
			if(obj != null) return obj.getScreenPosition(LuaUtils.cameraFromString(camera)).y;

			return 0;
		});
		addCallback("characterDance", function(character:String) {
			switch(character.toLowerCase()) {
				case 'dad': game.dad.dance();
				case 'gf' | 'girlfriend': if(game.gf != null) game.gf.dance();
				default: game.boyfriend.dance();
			}
		});

		addCallback("makeLuaSprite", function(tag:String, ?image:String = null, ?x:Float = 0, ?y:Float = 0) {
			tag = tag.replace('.', '');
			LuaUtils.destroyObject(tag);
			var leSprite:ModchartSprite = new ModchartSprite(x, y);
			if(image != null && image.length > 0)
			{
				leSprite.loadGraphic(Paths.image(image));
			}
			MusicBeatState.getVariables().set(tag, leSprite);
			leSprite.active = true;
		});
		addCallback("makeAnimatedLuaSprite", function(tag:String, ?image:String = null, ?x:Float = 0, ?y:Float = 0, ?spriteType:String = 'auto') {
			tag = tag.replace('.', '');
			LuaUtils.destroyObject(tag);
			var leSprite:ModchartSprite = new ModchartSprite(x, y);

			if(image != null && image.length > 0)
			{
				LuaUtils.loadFrames(leSprite, image, spriteType);
			}
			MusicBeatState.getVariables().set(tag, leSprite);
		});

		addCallback("makeGraphic", function(obj:String, width:Int = 256, height:Int = 256, color:String = 'FFFFFF') {
			var spr:FlxSprite = LuaUtils.getObjectDirectly(obj);
			if(spr != null) spr.makeGraphic(width, height, CoolUtil.colorFromString(color));
		});
		addCallback("addAnimationByPrefix", function(obj:String, name:String, prefix:String, framerate:Float = 24, loop:Bool = true) {
			var obj:FlxSprite = cast LuaUtils.getObjectDirectly(obj);
			if(obj != null && obj.animation != null)
			{
				obj.animation.addByPrefix(name, prefix, framerate, loop);
				if(obj.animation.curAnim == null)
				{
					var dyn:Dynamic = cast obj;
					if(dyn.playAnim != null) dyn.playAnim(name, true);
					else dyn.animation.play(name, true);
				}
				return true;
			}
			return false;
		});

		addCallback("addAnimation", function(obj:String, name:String, frames:Any, framerate:Float = 24, loop:Bool = true) {
			return LuaUtils.addAnimByIndices(obj, name, null, frames, framerate, loop);
		});

		addCallback("addAnimationByIndices", function(obj:String, name:String, prefix:String, indices:Any, framerate:Float = 24, loop:Bool = false) {
			return LuaUtils.addAnimByIndices(obj, name, prefix, indices, framerate, loop);
		});

		addCallback("playAnim", function(obj:String, name:String, ?forced:Bool = false, ?reverse:Bool = false, ?startFrame:Int = 0)
		{
			var obj:Dynamic = LuaUtils.getObjectDirectly(obj);
			if(obj.playAnim != null)
			{
				obj.playAnim(name, forced, reverse, startFrame);
				return true;
			}
			else
			{
				if(obj.anim != null) obj.anim.play(name, forced, reverse, startFrame); //FlxAnimate
				else obj.animation.play(name, forced, reverse, startFrame);
				return true;
			}
			return false;
		});
		addCallback("addOffset", function(obj:String, anim:String, x:Float, y:Float) {
			var obj:Dynamic = LuaUtils.getObjectDirectly(obj);
			if(obj != null && obj.addOffset != null)
			{
				obj.addOffset(anim, x, y);
				return true;
			}
			return false;
		});

		addCallback("setScrollFactor", function(obj:String, scrollX:Float, scrollY:Float) {
			if(game.getLuaObject(obj) != null) {
				game.getLuaObject(obj).scrollFactor.set(scrollX, scrollY);
				return;
			}

			var object:FlxObject = Reflect.getProperty(LuaUtils.getTargetInstance(), obj);
			if(object != null) {
				object.scrollFactor.set(scrollX, scrollY);
			}
		});
		addCallback("addLuaSprite", function(tag:String, ?inFront:Bool = false) {
			var mySprite:FlxObject = MusicBeatState.getVariables().get(tag);
			if(mySprite == null) return;

			var instance = LuaUtils.getTargetInstance();
			if(inFront)
				instance.add(mySprite);
			else
			{
				if(PlayState.instance == null || ((game.health <= 0 && game.canDie) || (game.health >= game.maxHealth && game.canDadDie)))
					instance.insert(instance.members.indexOf(PlayState.instance.characterGroup), mySprite);
				else
					GameOverSubstate.instance.insert(GameOverSubstate.instance.members.indexOf(GameOverSubstate.instance.character), mySprite);
			}
		});
		addCallback("setGraphicSize", function(obj:String, x:Int = 0, y:Int = 0, updateHitbox:Bool = true) {
			if(game.getLuaObject(obj)!=null) {
				var shit:FlxSprite = game.getLuaObject(obj);
				shit.setGraphicSize(x, y);
				if(updateHitbox) shit.updateHitbox();
				return;
			}

			var split:Array<String> = obj.split('.');
			var poop:FlxSprite = LuaUtils.getObjectDirectly(split[0]);
			if(split.length > 1) {
				poop = LuaUtils.getVarInArray(LuaUtils.getPropertyLoop(split), split[split.length-1]);
			}

			if(poop != null) {
				poop.setGraphicSize(x, y);
				if(updateHitbox) poop.updateHitbox();
				return;
			}
			luaTrace('setGraphicSize: Couldnt find object: ' + obj, false, false, FlxColor.RED);
		});
		addCallback("scaleObject", function(obj:String, x:Float, y:Float, updateHitbox:Bool = true) {
			if(game.getLuaObject(obj)!=null) {
				var shit:FlxSprite = game.getLuaObject(obj);
				shit.scale.set(x, y);
				if(updateHitbox) shit.updateHitbox();
				return;
			}

			var split:Array<String> = obj.split('.');
			var poop:FlxSprite = LuaUtils.getObjectDirectly(split[0]);
			if(split.length > 1) {
				poop = LuaUtils.getVarInArray(LuaUtils.getPropertyLoop(split), split[split.length-1]);
			}

			if(poop != null) {
				poop.scale.set(x, y);
				if(updateHitbox) poop.updateHitbox();
				return;
			}
			luaTrace('scaleObject: Couldnt find object: ' + obj, false, false, FlxColor.RED);
		});
		addCallback("updateHitbox", function(obj:String) {
			if(game.getLuaObject(obj)!=null) {
				var shit:FlxSprite = game.getLuaObject(obj);
				shit.updateHitbox();
				return;
			}

			var split:Array<String> = obj.split('.');
			var poop:FlxSprite = LuaUtils.getObjectDirectly(split[0]);
			if(split.length > 1) {
				poop = LuaUtils.getVarInArray(LuaUtils.getPropertyLoop(split), split[split.length-1]);
			}

			if(poop != null) {
				poop.updateHitbox();
				return;
			}
			luaTrace('updateHitbox: Couldnt find object: ' + obj, false, false, FlxColor.RED);
		});

		addCallback("removeLuaSprite", function(tag:String, destroy:Bool = true, ?group:String = null) {
			var obj:FlxSprite = LuaUtils.getObjectDirectly(tag);
			if(obj == null || obj.destroy == null)
				return;
			
			var groupObj:Dynamic = null;
			if(group == null) groupObj = LuaUtils.getTargetInstance();
			else groupObj = LuaUtils.getObjectDirectly(group);

			groupObj.remove(obj, true);
			if(destroy)
			{
				MusicBeatState.getVariables().remove(tag);
				obj.destroy();
			}
		});

		addCallback("luaSpriteExists", function(tag:String) {
			var obj:FlxSprite = MusicBeatState.getVariables().get(tag);
			return (obj != null && (Std.isOfType(obj, ModchartSprite)));
		});
		addCallback("luaTextExists", function(tag:String) {
			var obj:FlxText = MusicBeatState.getVariables().get(tag);
			return (obj != null && Std.isOfType(obj, FlxText));
		});
		addCallback("luaSoundExists", function(tag:String) {
			var obj:FlxSound = MusicBeatState.getVariables().get('sound_$tag');
			return (obj != null && Std.isOfType(obj, FlxSound));
		});

		addCallback("setHealthBarColors", function(left:String, right:String) {
			var left_color:Null<FlxColor> = null;
			var right_color:Null<FlxColor> = null;
			if (left != null && left != '')
				left_color = CoolUtil.colorFromString(left);
			if (right != null && right != '')
				right_color = CoolUtil.colorFromString(right);
			game.healthBar.createFilledBar(left_color, right_color);
		});
		/*
		addCallback("setTimeBarColors", function(left:String, right:String) {
			var left_color:Null<FlxColor> = null;
			var right_color:Null<FlxColor> = null;
			if (left != null && left != '')
				left_color = CoolUtil.colorFromString(left);
			if (right != null && right != '')
				right_color = CoolUtil.colorFromString(right);
			game.hud.timeBar.createFilledBar(left_color, right_color);
		});
		*/

		addCallback("setObjectCamera", function(obj:String, camera:String = 'game') {
			var real:FlxBasic = game.getLuaObject(obj);
			if(real != null) {
				real.cameras = [LuaUtils.cameraFromString(camera)];
				return true;
			}

			var split:Array<String> = obj.split('.');
			var object:FlxBasic = LuaUtils.getObjectDirectly(split[0]);
			if(split.length > 1) {
				object = LuaUtils.getVarInArray(LuaUtils.getPropertyLoop(split), split[split.length-1]);
			}

			if(object != null) {
				object.cameras = [LuaUtils.cameraFromString(camera)];
				return true;
			}
			luaTrace("setObjectCamera: Object " + obj + " doesn't exist!", false, false, FlxColor.RED);
			return false;
		});
		addCallback("setBlendMode", function(obj:String, blend:String = '') {
			var real:FlxSprite = game.getLuaObject(obj);
			if(real != null) {
				real.blend = LuaUtils.blendModeFromString(blend);
				return true;
			}

			var split:Array<String> = obj.split('.');
			var spr:FlxSprite = LuaUtils.getObjectDirectly(split[0]);
			if(split.length > 1) {
				spr = LuaUtils.getVarInArray(LuaUtils.getPropertyLoop(split), split[split.length-1]);
			}

			if(spr != null) {
				spr.blend = LuaUtils.blendModeFromString(blend);
				return true;
			}
			luaTrace("setBlendMode: Object " + obj + " doesn't exist!", false, false, FlxColor.RED);
			return false;
		});
		addCallback("screenCenter", function(obj:String, pos:String = 'xy') {
			var spr:FlxObject = game.getLuaObject(obj);

			if(spr==null){
				var split:Array<String> = obj.split('.');
				spr = LuaUtils.getObjectDirectly(split[0]);
				if(split.length > 1) {
					spr = LuaUtils.getVarInArray(LuaUtils.getPropertyLoop(split), split[split.length-1]);
				}
			}

			if(spr != null)
			{
				switch(pos.trim().toLowerCase())
				{
					case 'x':
						spr.screenCenter(X);
						return;
					case 'y':
						spr.screenCenter(Y);
						return;
					default:
						spr.screenCenter(XY);
						return;
				}
			}
			luaTrace("screenCenter: Object " + obj + " doesn't exist!", false, false, FlxColor.RED);
		});
		addCallback("objectsOverlap", function(obj1:String, obj2:String) {
			var namesArray:Array<String> = [obj1, obj2];
			var objectsArray:Array<FlxBasic> = [];
			for (i in 0...namesArray.length)
			{
				var real:FlxBasic = game.getLuaObject(namesArray[i]);
				if(real != null)
					objectsArray.push(real);
				else
					objectsArray.push(Reflect.getProperty(LuaUtils.getTargetInstance(), namesArray[i]));
			}
			return (!objectsArray.contains(null) && FlxG.overlap(objectsArray[0], objectsArray[1]));
		});
		addCallback("getPixelColor", function(obj:String, x:Int, y:Int) {
			var split:Array<String> = obj.split('.');
			var spr:FlxSprite = LuaUtils.getObjectDirectly(split[0]);
			if(split.length > 1) {
				spr = LuaUtils.getVarInArray(LuaUtils.getPropertyLoop(split), split[split.length-1]);
			}

			if(spr != null) return spr.pixels.getPixel32(x, y);
			return FlxColor.BLACK;
		});
		addCallback("startVideo", function(videoFile:String, ?canSkip:Bool = true, ?forMidSong:Bool = false, ?shouldLoop:Bool = false, ?playOnLoad:Bool = true) {
			#if VIDEOS_ALLOWED
			game.startVideo(videoFile);

			#else
			PlayState.instance.inCutscene = true;
			new FlxTimer().start(0.1, function(tmr:FlxTimer)
			{
				PlayState.instance.inCutscene = false;
				if(game.endingSong)
					game.endSong();
				else
					game.startCountdown();
			});
			return true;
			#end
		});

		addCallback("playMusic", function(sound:String, ?volume:Float = 1, ?loop:Bool = false) {
			FlxG.sound.playMusic(Paths.music(sound), volume, loop);
		});
		addCallback("playSound", function(sound:String, ?volume:Float = 1, ?tag:String = null, ?loop:Bool = false) {
			if(tag != null && tag.length > 0)
			{
				var originalTag:String = tag;
				tag = LuaUtils.formatVariable('sound_$tag');
				var variables = MusicBeatState.getVariables();
				var oldSnd = variables.get(tag);
				if(oldSnd != null)
				{
					oldSnd.stop();
					oldSnd.destroy();
				}

				variables.set(tag, FlxG.sound.play(Paths.sound(sound), volume, loop, null, true, function()
				{
					if(!loop) variables.remove(tag);
					if(game != null) game.scripts.call('onSoundFinished', [originalTag]);
				}));
				return tag;
			}
			FlxG.sound.play(Paths.sound(sound), volume);
			return null;
		});
		addCallback("stopSound", function(tag:String) {
			if(tag == null || tag.length < 1)
			{
				if(FlxG.sound.music != null)
					FlxG.sound.music.stop();
			}
			else
			{
				tag = LuaUtils.formatVariable('sound_$tag');
				var variables = MusicBeatState.getVariables();
				var snd:FlxSound = variables.get(tag);
				if(snd != null)
				{
					snd.stop();
					variables.remove(tag);
				}
			}
		});
		addCallback("pauseSound", function(tag:String) {
			if(tag == null || tag.length < 1)
			{
				if(FlxG.sound.music != null)
					FlxG.sound.music.pause();
			}
			else
			{
				tag = LuaUtils.formatVariable('sound_$tag');
				var snd:FlxSound = MusicBeatState.getVariables().get(tag);
				if(snd != null) snd.pause();
			}
		});
		addCallback("resumeSound", function(tag:String) {
			if(tag == null || tag.length < 1)
			{
				if(FlxG.sound.music != null)
					FlxG.sound.music.play();
			}
			else
			{
				tag = LuaUtils.formatVariable('sound_$tag');
				var snd:FlxSound = MusicBeatState.getVariables().get(tag);
				if(snd != null) snd.play();
			}
		});
		addCallback("soundFadeIn", function(tag:String, duration:Float, fromValue:Float = 0, toValue:Float = 1) {
			if(tag == null || tag.length < 1)
			{
				if(FlxG.sound.music != null)
					FlxG.sound.music.fadeIn(duration, fromValue, toValue);
			}
			else
			{
				tag = LuaUtils.formatVariable('sound_$tag');
				var snd:FlxSound = MusicBeatState.getVariables().get(tag);
				if(snd != null)
					snd.fadeIn(duration, fromValue, toValue);
			}
		});
		addCallback("soundFadeOut", function(tag:String, duration:Float, toValue:Float = 0) {
			if(tag == null || tag.length < 1)
			{
				if(FlxG.sound.music != null)
					FlxG.sound.music.fadeOut(duration, toValue);
			}
			else
			{
				tag = LuaUtils.formatVariable('sound_$tag');
				var snd:FlxSound = MusicBeatState.getVariables().get(tag);
				if(snd != null)
					snd.fadeOut(duration, toValue);
			}
		});
		addCallback("soundFadeCancel", function(tag:String) {
			if(tag == null || tag.length < 1)
			{
				if(FlxG.sound.music != null && FlxG.sound.music.fadeTween != null)
					FlxG.sound.music.fadeTween.cancel();
			}
			else
			{
				tag = LuaUtils.formatVariable('sound_$tag');
				var snd:FlxSound = MusicBeatState.getVariables().get(tag);
				if(snd != null && snd.fadeTween != null)
					snd.fadeTween.cancel();
			}
		});
		addCallback("getSoundVolume", function(tag:String) {
			if(tag == null || tag.length < 1)
			{
				if(FlxG.sound.music != null)
					return FlxG.sound.music.volume;
			}
			else
			{
				tag = LuaUtils.formatVariable('sound_$tag');
				var snd:FlxSound = MusicBeatState.getVariables().get(tag);
				if(snd != null) return snd.volume;
			}
			return 0;
		});
		addCallback("setSoundVolume", function(tag:String, value:Float) {
			if(tag == null || tag.length < 1)
			{
				tag = LuaUtils.formatVariable('sound_$tag');
				if(FlxG.sound.music != null)
				{
					FlxG.sound.music.volume = value;
					return;
				}
			}
			else
			{
				tag = LuaUtils.formatVariable('sound_$tag');
				var snd:FlxSound = MusicBeatState.getVariables().get(tag);
				if(snd != null) snd.volume = value;
			}
		});
		addCallback("getSoundTime", function(tag:String) {
			if(tag == null || tag.length < 1)
			{
				return FlxG.sound.music != null ? FlxG.sound.music.time : 0;
			}
			tag = LuaUtils.formatVariable('sound_$tag');
			var snd:FlxSound = MusicBeatState.getVariables().get(tag);
			return snd != null ? snd.time : 0;
		});
		addCallback("setSoundTime", function(tag:String, value:Float) {
			if(tag == null || tag.length < 1)
			{
				if(FlxG.sound.music != null)
				{
					FlxG.sound.music.time = value;
					return;
				}
			}
			else
			{
				tag = LuaUtils.formatVariable('sound_$tag');
				var snd:FlxSound = MusicBeatState.getVariables().get(tag);
				if(snd != null) snd.time = value;
			}
		});
		addCallback("getSoundPitch", function(tag:String) {
			#if FLX_PITCH
			tag = LuaUtils.formatVariable('sound_$tag');
			var snd:FlxSound = MusicBeatState.getVariables().get(tag);
			return snd != null ? snd.pitch : 1;
			#else
			luaTrace("getSoundPitch: Sound Pitch is not supported on this platform!", false, false, FlxColor.RED);
			return 1;
			#end
		});
		addCallback("setSoundPitch", function(tag:String, value:Float, ?doPause:Bool = false) {
			#if FLX_PITCH
			tag = LuaUtils.formatVariable('sound_$tag');
			var snd:FlxSound = MusicBeatState.getVariables().get(tag);
			if(snd != null)
			{
				var wasResumed:Bool = snd.playing;
				if (doPause) snd.pause();
				snd.pitch = value;
				if (doPause && wasResumed) snd.play();
			}
			
			if(tag == null || tag.length < 1)
			{
				if(FlxG.sound.music != null)
				{
					var wasResumed:Bool = FlxG.sound.music.playing;
					if (doPause) FlxG.sound.music.pause();
					FlxG.sound.music.pitch = value;
					if (doPause && wasResumed) FlxG.sound.music.play();
					return;
				}
			}
			else
			{
				var snd:FlxSound = MusicBeatState.getVariables().get(tag);
				if(snd != null)
				{
					var wasResumed:Bool = snd.playing;
					if (doPause) snd.pause();
					snd.pitch = value;
					if (doPause && wasResumed) snd.play();
				}
			}
			#else
			luaTrace("setSoundPitch: Sound Pitch is not supported on this platform!", false, false, FlxColor.RED);
			#end
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

	public function resultIsAllowed(leLua:State, leResult:Null<Int>) { //Makes it ignore warnings
		return switch(Lua.type(leLua, leResult)) {
			case Lua.LUA_TNIL | Lua.LUA_TBOOLEAN | Lua.LUA_TNUMBER | Lua.LUA_TSTRING | Lua.LUA_TTABLE :
				true;
			default:
				false;
		}
	}

	public static function getBool(variable:String):Bool {
		if(lastCalledScript == null) return false;

		var lua:State = lastCalledScript.lua;
		if(lua == null) return false;

		var result:String = null;
		Lua.getglobal(lua, variable);
		result = Convert.fromLua(lua, -1);
		Lua.pop(lua, 1);

		if (result == null)
			return false;

		// YES! FINALLY IT WORKS
		//trace('variable: ' + variable + ', ' + result);
		return (result == 'true');
	}

	public function getErrorMessage() {
		var v:String = Lua.tostring(lua, -1);
		Lua.pop(lua, 1);
		return v;
	}

	public function findScript(scriptFile:String, ext:String = '.lua')
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

}
#end