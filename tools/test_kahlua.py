"""Execute text processing in the installed game's actual Kahlua engine."""
from pathlib import Path
import sys, os
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(Path.home()/'AppData/Local/Temp/KnoxNavigatorRuntime'))
import jpype
GAME=Path('D:/steam/steamapps/common/ProjectZomboid')
os.chdir(GAME)
jpype.startJVM(str(GAME/'jre64/bin/server/jvm.dll'),'--enable-native-access=ALL-UNNAMED',classpath=[str(GAME/'projectzomboid.jar')])
Platform=jpype.JClass('se.krka.kahlua.j2se.J2SEPlatform')
Thread=jpype.JClass('se.krka.kahlua.vm.KahluaThread')
Compiler=jpype.JClass('se.krka.kahlua.luaj.compiler.LuaCompiler')
platform=Platform.getInstance()
env=platform.newEnvironment()
thread=Thread(platform,env)
owner=Thread.class_.getDeclaredField('debugOwnerThread')
owner.setAccessible(True)
owner.set(thread,jpype.JClass('java.lang.Thread').currentThread())
def execute(source,name):
    stream=jpype.JClass('java.io.ByteArrayInputStream')(source.encode('utf-8'))
    reader=jpype.JClass('java.io.InputStreamReader')(stream,'UTF-8' if name.endswith('.lua') else 'ISO-8859-1')
    closure=Compiler.loadis(reader,name,env)
    result=thread.pcall(closure,jpype.JArray(jpype.JClass('java.lang.Object'))([]))
    assert bool(result[0]),[str(item) for item in result]
media=ROOT/'KnoxNavigator/42/media'
env.rawset('TestPOIData',jpype.JString((media/'data/KnoxNavigator/pois.tsv').read_text(encoding='utf-8')))
execute('require=function() end','stub')
execute((media/'lua/shared/KnoxNavigator/Core.lua').read_text(encoding='utf-8'),'Core.lua')
execute('''
getModFileReader=function()
 local lines=KnoxNavigator.split(TestPOIData,"\\n")
 local reader={index=0}
 reader.readLine=function(self) self.index=self.index+1;return lines[self.index] end
 reader.close=function() end
 return reader
end
assert(KnoxNavigator.normalize('  100% GIFT SHOP СУВЕНИРЫ  ')== '100% gift shop сувениры')
assert(KnoxNavigator.normalize('Wholesale 50%')=='wholesale 50%')
assert(KnoxNavigator.loadPOIs())
assert(#KnoxNavigator.pois==1647)
assert(#KnoxNavigator.search('Gift Shop',6450,5430)==24)
assert(#KnoxNavigator.search('СУВЕНИРЫ',6450,5430)==24)
assert(#KnoxNavigator.search('  gift shop riverside  ',6450,5430)>0)
''','real-engine-regression')
print('Actual game Kahlua engine: all 1647 POIs load; 24 Gift Shops; Cyrillic, percent signs and whitespace pass.')
env.rawset('TestRoadData',jpype.JString((media/'data/KnoxNavigator/roads.tsv').read_text(encoding='utf-8')))
env.rawset('TestStatusText',jpype.JString('Правый клик — выбрать цель'))
env.rawset('TestSearchTitle',jpype.JString('Найти место — ближайшие первыми'))
execute('''
getModFileReader=function(id,path)
 local data=string.find(path,'roads.tsv',1,true) and TestRoadData or TestPOIData
 local reader={index=0,lines=KnoxNavigator.split(data,"\\n")}
 reader.readLine=function(self) self.index=self.index+1;return self.lines[self.index] end
 reader.close=function() end
 return reader
end
''','data-stub')
execute((ROOT/'tools/ui_harness.lua').read_text(encoding='utf-8'),'ui-harness')
execute('getTexture=function() return nil end','texture-stub')
for name in ['shared/KnoxNavigator/MapMeta.lua','client/KnoxNavigator/Router.lua','client/KnoxNavigator/Options.lua','client/KnoxNavigator/UI.lua','client/KnoxNavigator/Main.lua']:
    execute((media/'lua'/name).read_text(encoding='utf-8'),name)
execute('''
Events.OnGameStart.handler()
assert(KnoxNavigator.status==TestStatusText,'Russian HUD text must survive the game compiler')
while KnoxNavigator.Router.loading do Events.OnTickEvenPaused.handler() end
assert(KnoxNavigator.window.visible)
TestPlayer.vehicle=nil
Events.OnTickEvenPaused.handler()
assert(KnoxNavigator.window.visible==false)
for index=1,100 do Events.OnTickEvenPaused.handler();assert(KnoxNavigator.window.visible==false) end
TestPlayer.vehicle={}
Events.OnTickEvenPaused.handler()
assert(KnoxNavigator.window.visible==true)
KnoxNavigator.showSearch()
assert(KnoxNavigator.searchWindow.title==TestSearchTitle,'Russian search title must survive the game compiler')
KnoxNavigator.searchWindow.entry:setText('Gift Shop')
KnoxNavigator.searchWindow:search()
assert(#KnoxNavigator.searchWindow.list.items==24)
KnoxNavigator.searchWindow:routeSelected()
while KnoxNavigator.Router.job do Events.OnTickEvenPaused.handler() end
assert(KnoxNavigator.route)
KnoxNavigator.window.map:render()
assert(TestRepaintCount>0)
KnoxNavigator.showSettings()
KnoxNavigator.settingsWindow:apply()
KnoxNavigator.settingsWindow:close()
KnoxNavigator.showSearch()
TestPlayer.vehicle=nil
Events.OnTickEvenPaused.handler()
assert(KnoxNavigator.searchWindow==nil,'search must close when leaving the vehicle')
assert(KnoxNavigator.window.visible==false)
TestPlayer.vehicle={}
Events.OnTickEvenPaused.handler()
assert(KnoxNavigator.window.visible==true)
''','startup-and-route')
print('Actual game Kahlua engine: startup, road loading, search window, selected route, map handlers and settings pass (native ISUI replaced by test doubles).')
jpype.shutdownJVM()
