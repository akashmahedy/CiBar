#pragma once
#include <nlohmann/json.hpp>
#include <algorithm>
#include <chrono>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <functional>
#include <map>
#include <optional>
#include <random>
#include <set>
#include <stdexcept>
#include <string>
#include <vector>
#ifdef _WIN32
#define NOMINMAX
#include <windows.h>
#endif
namespace cibar {
using json=nlohmann::json; namespace fs=std::filesystem;
inline void require(bool value,const std::string& message){if(!value)throw std::runtime_error(message);}
struct Example {std::string hanzi,pinyin,english,attribution,sourceURL;bool pinyinAutomatic=false;};
NLOHMANN_DEFINE_TYPE_NON_INTRUSIVE(Example,hanzi,pinyin,english,attribution,sourceURL,pinyinAutomatic)
struct Word {std::string id,pack;int level=0,serial=0;std::string hanzi,pinyin,english,source,note;std::optional<Example> example;};
inline void to_json(json& j,const Word& w){j={{"id",w.id},{"pack",w.pack},{"level",w.level},{"serial",w.serial},{"hanzi",w.hanzi},{"pinyin",w.pinyin},{"english",w.english},{"source",w.source},{"note",w.note}};if(w.example)j["example"]=*w.example;}
inline void from_json(const json& j,Word& w){j.at("id").get_to(w.id);j.at("pack").get_to(w.pack);j.at("level").get_to(w.level);j.at("serial").get_to(w.serial);j.at("hanzi").get_to(w.hanzi);j.at("pinyin").get_to(w.pinyin);j.at("english").get_to(w.english);j.at("source").get_to(w.source);j.at("note").get_to(w.note);if(j.contains("example")&&!j["example"].is_null())w.example=j["example"].get<Example>();else w.example.reset();}
struct Range {int start=1,end=1;};
NLOHMANN_DEFINE_TYPE_NON_INTRUSIVE(Range,start,end)
struct Settings {
 std::string pack="hsk2025";std::vector<int> levels{4};std::map<std::string,Range> ranges;
 double interval=45;bool random=false,favoritesOnly=false,showLevel=true,showSerial=true,showHanzi=true,showPinyin=true,showMeaning=true,showFill=true,highlight=true,adaptiveWidth=true;
 double fontSize=13,width=260;std::string preset="Ocean",contrast="Soft",customColor="5A919C";
 void validate(){require(std::isfinite(interval)&&interval>=1&&interval<=86400,"Delay must be 1–86400 seconds.");require(std::isfinite(fontSize)&&fontSize>=9&&fontSize<=18,"Font must be 9–18 pt.");require(std::isfinite(width)&&width>=80&&width<=600,"Width must be 80–600.");require(!pack.empty()&&!levels.empty(),"Select at least one level.");for(int l:levels)require(l>=0&&l<=6,"Invalid HSK level.");std::sort(levels.begin(),levels.end());levels.erase(std::unique(levels.begin(),levels.end()),levels.end());for(auto&[key,r]:ranges)require(r.start>=1&&r.end>=r.start,"Range needs End >= Start >= 1.");require(std::set<std::string>{"Ocean","Sage","Plum","Amber","Graphite","Custom"}.contains(preset),"Unknown preset.");require(std::set<std::string>{"Soft","Balanced","Strong"}.contains(contrast),"Unknown contrast.");require(customColor.size()==6&&customColor.find_first_not_of("0123456789abcdefABCDEF")==std::string::npos,"Custom color needs six hex digits.");}
 std::string key()const{auto ls=levels;std::sort(ls.begin(),ls.end());std::string r;for(int l:ls){if(!r.empty())r+=",";auto it=ranges.find(std::to_string(l));r+=std::to_string(l)+":"+std::to_string(it==ranges.end()?1:it->second.start)+"-"+std::to_string(it==ranges.end()?99999:it->second.end);}return pack+"|"+r+"|"+(random?"true":"false")+"|"+(favoritesOnly?"true":"false");}
 std::string title(const Word& w)const{std::vector<std::string> p;if(showLevel&&w.level>0)p.push_back("H"+std::to_string(w.level));if(showSerial)p.push_back(std::to_string(w.serial));if(showHanzi)p.push_back(w.hanzi);if(showPinyin)p.push_back(w.pinyin);if(showMeaning)p.push_back(w.english);std::string s;for(auto&x:p){if(!s.empty())s+=" · ";s+=x;}return s.empty()?"CíBar":s;}
};
NLOHMANN_DEFINE_TYPE_NON_INTRUSIVE(Settings,pack,levels,ranges,interval,random,favoritesOnly,showLevel,showSerial,showHanzi,showPinyin,showMeaning,showFill,highlight,adaptiveWidth,fontSize,width,preset,contrast,customColor)
struct Snapshot {std::vector<std::string> order;int index=0;double remaining=45;bool manuallyPaused=false;};
NLOHMANN_DEFINE_TYPE_NON_INTRUSIVE(Snapshot,order,index,remaining,manuallyPaused)
struct SavedData {int schemaVersion=1;Settings settings;std::set<std::string> favorites;std::vector<Word> customWords;std::map<std::string,Snapshot> sessions;bool migratedSwiftBar=false;};
NLOHMANN_DEFINE_TYPE_NON_INTRUSIVE(SavedData,schemaVersion,settings,favorites,customWords,sessions,migratedSwiftBar)
struct Backup {std::string format="CiBarBackup";int version=1;double createdAt=std::chrono::duration<double>(std::chrono::system_clock::now().time_since_epoch()).count()-978307200.0;SavedData data;std::vector<Word> words;std::string licenses;};
NLOHMANN_DEFINE_TYPE_NON_INTRUSIVE(Backup,format,version,createdAt,data,words,licenses)
inline std::string trim(std::string s){auto a=s.find_first_not_of(" \t\r\n");return a==std::string::npos?"":s.substr(a,s.find_last_not_of(" \t\r\n")-a+1);}
inline void validateWords(const std::vector<Word>& words,bool empty=false){require(empty||!words.empty(),"Word list is empty.");std::set<std::string> ids,serials;for(auto&w:words){require(!w.id.empty()&&!w.pack.empty()&&w.level>=0&&w.level<=6&&w.serial>0&&!trim(w.hanzi).empty()&&!trim(w.pinyin).empty()&&!trim(w.english).empty()&&ids.insert(w.id).second&&serials.insert(w.pack+":"+std::to_string(w.level)+":"+std::to_string(w.serial)).second,"Invalid or duplicate word: "+w.hanzi);if(w.example)require(!trim(w.example->hanzi).empty()&&!trim(w.example->pinyin).empty()&&!trim(w.example->english).empty(),"Incomplete example.");}}
inline void validateData(SavedData& d){require(d.schemaVersion==1,"Unsupported settings version.");d.settings.validate();validateWords(d.customWords,true);for(auto&[k,s]:d.sessions){require(std::isfinite(s.remaining)&&s.remaining>=0&&s.index>=0&&s.index<=int(s.order.size())&&(s.order.empty()||s.index<int(s.order.size())),"Invalid saved progress.");require(std::set<std::string>(s.order.begin(),s.order.end()).size()==s.order.size(),"Duplicate saved progress IDs.");}}
inline Backup decodeBackup(const json& j){Backup b=j.get<Backup>();require(b.format=="CiBarBackup"&&b.version==1&&std::isfinite(b.createdAt),"Unsupported backup format.");validateData(b.data);validateWords(b.words);auto all=b.words;all.insert(all.end(),b.data.customWords.begin(),b.data.customWords.end());validateWords(all);return b;}
class Playback {
 std::function<double()> clock;std::optional<double> started;std::set<std::string> blockers;std::mt19937 rng{std::random_device{}()};
 public:std::vector<Word> words;int index=0;double remaining=45,interval=45;bool manual=false,random=false;
 explicit Playback(std::function<double()> c=[] {return std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch()).count();}):clock(std::move(c)){}
 bool paused()const{return manual||!blockers.empty();}const Word* current()const{return words.empty()?nullptr:&words.at(index);}double left()const{return std::max(0.0,remaining-(started?clock()-*started:0));}double fraction()const{return std::clamp(left()/interval,0.0,1.0);}
 static std::vector<Word> select(const std::vector<Word>& all,const Settings&s,const std::set<std::string>& fav){std::vector<Word> out;for(auto&w:all){auto r=s.ranges.find(std::to_string(w.level));if(w.pack==s.pack&&std::find(s.levels.begin(),s.levels.end(),w.level)!=s.levels.end()&&(!s.favoritesOnly||fav.contains(w.id))&&(r==s.ranges.end()||(w.serial>=r->second.start&&w.serial<=r->second.end)))out.push_back(w);}std::sort(out.begin(),out.end(),[](auto&a,auto&b){return a.level==b.level?a.serial<b.serial:a.level<b.level;});return out;}
 void restartClock(){started=paused()||words.empty()?std::nullopt:std::optional<double>(clock());}
 void configure(std::vector<Word> selected,const Settings&s,const std::optional<Snapshot>& snap){words=std::move(selected);index=0;remaining=interval=s.interval;random=s.random;manual=false;if(snap&&!words.empty()){if(random){std::map<std::string,Word> lookup;for(auto&w:words)lookup[w.id]=w;std::set<std::string> keys;for(auto&w:words)keys.insert(w.id);if(std::set<std::string>(snap->order.begin(),snap->order.end())==keys&&snap->order.size()==words.size()){words.clear();for(auto&id:snap->order)words.push_back(lookup.at(id));}else std::shuffle(words.begin(),words.end(),rng);}if(snap->index>=0&&snap->index<int(snap->order.size())){auto id=snap->order[snap->index];for(size_t i=0;i<words.size();i++)if(words[i].id==id){index=int(i);remaining=std::clamp(snap->remaining,0.01,interval);break;}}manual=snap->manuallyPaused;}else if(random)std::shuffle(words.begin(),words.end(),rng);restartClock();}
 Snapshot snapshot()const{Snapshot s;for(auto&w:words)s.order.push_back(w.id);s.index=index;s.remaining=left();s.manuallyPaused=manual;return s;}
 void block(const std::string& key,bool active){remaining=left();if(active)blockers.insert(key);else blockers.erase(key);restartClock();}
 void toggle(){remaining=left();manual=!manual;restartClock();}
 void advance(int direction=1){if(words.empty())return;if(direction>0&&index==int(words.size())-1&&random){auto old=current()->id;std::shuffle(words.begin(),words.end(),rng);if(words.size()>1&&words[0].id==old)std::swap(words[0],words[1]);}index=(index+direction+int(words.size()))%int(words.size());remaining=interval;restartClock();}
 bool jump(const std::string&id){for(size_t i=0;i<words.size();i++)if(words[i].id==id){index=int(i);remaining=interval;restartClock();return true;}return false;}
 void changeInterval(double value){require(std::isfinite(value)&&value>=1&&value<=86400,"Invalid delay.");remaining=left()/interval*value;interval=value;restartClock();}
};
inline std::vector<std::vector<std::string>> parseDelimited(const std::string& input,char delimiter){std::vector<std::vector<std::string>> rows;std::vector<std::string> row;std::string cell;bool quoted=false,closed=false;auto endRow=[&]{row.push_back(cell);cell.clear();if(std::any_of(row.begin(),row.end(),[](auto&s){return !s.empty();}))rows.push_back(row);row.clear();closed=false;};for(size_t i=0;i<input.size();i++){char ch=input[i];if(ch=='"'){if(quoted&&i+1<input.size()&&input[i+1]=='"'){cell+='"';i++;}else if(quoted){quoted=false;closed=true;}else if(cell.empty()&&!closed)quoted=true;else throw std::runtime_error("Invalid CSV quote.");}else if(ch==delimiter&&!quoted){row.push_back(cell);cell.clear();closed=false;}else if((ch=='\r'||ch=='\n')&&!quoted){if(ch=='\r'&&i+1<input.size()&&input[i+1]=='\n')i++;endRow();}else{require(!closed,"Characters after a CSV closing quote.");cell+=ch;}}require(!quoted,"CSV quote is not closed.");endRow();return rows;}
inline std::vector<Word> importWords(const std::string& text,char delimiter,const std::string& pack){auto rows=parseDelimited(text,delimiter);require(!rows.empty(),"Import file is empty.");auto keys=rows.front();if(!keys.empty()&&keys[0].starts_with("\xef\xbb\xbf"))keys[0].erase(0,3);for(auto&k:keys){k=trim(k);std::transform(k.begin(),k.end(),k.begin(),[](unsigned char c){return char(std::tolower(c));});}require(std::set<std::string>(keys.begin(),keys.end()).size()==keys.size(),"Duplicate column names.");for(auto k:{"serial","hanzi","pinyin","english"})require(std::find(keys.begin(),keys.end(),k)!=keys.end(),"Required columns: serial, hanzi, pinyin, english.");std::vector<Word> out;for(size_t n=1;n<rows.size();n++){require(rows[n].size()==keys.size(),"Wrong column count at row "+std::to_string(n+1));std::map<std::string,std::string> f;for(size_t i=0;i<keys.size();i++)f[keys[i]]=rows[n][i];size_t consumed=0;int serial=std::stoi(f["serial"],&consumed);require(consumed==f["serial"].size(),"Invalid serial.");Word w;w.id=pack+":"+std::to_string(serial);w.pack=pack;w.serial=serial;w.hanzi=f["hanzi"];w.pinyin=f["pinyin"];w.english=f["english"];w.source="User import";bool has=!f["example_hanzi"].empty()||!f["example_pinyin"].empty()||!f["example_english"].empty();if(has){require(!f["example_hanzi"].empty()&&!f["example_pinyin"].empty()&&!f["example_english"].empty(),"Example needs all three example columns.");w.example=Example{f["example_hanzi"],f["example_pinyin"],f["example_english"],"User import","",false};}out.push_back(w);}validateWords(out);return out;}
inline std::string readText(const fs::path& path){std::ifstream f(path,std::ios::binary);require(bool(f),"Cannot read "+path.filename().string());return std::string(std::istreambuf_iterator<char>(f),{});}
inline void atomicText(const fs::path& path,const std::string& text){fs::create_directories(path.parent_path());auto temp=path;temp+=".tmp";{std::ofstream f(temp,std::ios::binary|std::ios::trunc);require(bool(f),"Cannot write "+path.filename().string());f.write(text.data(),std::streamsize(text.size()));f.flush();require(bool(f),"Backup write failed.");}
#ifdef _WIN32
 require(MoveFileExW(temp.c_str(),path.c_str(),MOVEFILE_REPLACE_EXISTING|MOVEFILE_WRITE_THROUGH)!=0,"Cannot replace saved file.");
#else
 fs::rename(temp,path);
#endif
}
class Store {
 public:fs::path directory;SavedData data;std::vector<Word> bundled;std::string licenses,warning;
 Store(fs::path dir,fs::path resources):directory(std::move(dir)){bundled=json::parse(readText(resources/"words.json")).get<std::vector<Word>>();validateWords(bundled);licenses=readText(resources/"ATTRIBUTIONS.txt");auto state=directory/"state.json";if(fs::exists(state)){try{data=json::parse(readText(state)).get<SavedData>();validateData(data);}catch(const std::exception&){fs::copy_file(state,directory/("state-recovery-"+stamp()+".json"));warning="Saved settings were invalid. Original settings were preserved in the data folder.";data=SavedData{};}}auto restored=directory/"restored-words.json";if(fs::exists(restored)){auto w=json::parse(readText(restored)).get<std::vector<Word>>();validateWords(w);bundled=std::move(w);}auto all=allWords();validateWords(all);}
 static std::string stamp(){return std::to_string(std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::system_clock::now().time_since_epoch()).count());}
 std::vector<Word> allWords()const{auto out=bundled;out.insert(out.end(),data.customWords.begin(),data.customWords.end());return out;}
 void save(){atomicText(directory/"state.json",json(data).dump(2));}
 Backup backup()const{Backup b;b.data=data;b.words=bundled;b.licenses=licenses;return b;}
 void restore(const json& raw,std::function<void(const fs::path&,const std::string&)> writer=atomicText){auto b=decodeBackup(raw);auto recovery=directory/("before-restore-"+stamp()+".json");writer(recovery,json(backup()).dump(2));auto old=data;auto words=bundled;auto oldLicense=licenses;bool hadRestore=fs::exists(directory/"restored-words.json");try{writer(directory/"restored-words.json",json(b.words).dump());writer(directory/"state.json",json(b.data).dump(2));writer(directory/"restored-licenses.txt",b.licenses);data=std::move(b.data);bundled=std::move(b.words);licenses=std::move(b.licenses);}catch(...){atomicText(directory/"state.json",json(old).dump(2));if(hadRestore)atomicText(directory/"restored-words.json",json(words).dump());else if(fs::exists(directory/"restored-words.json"))fs::remove(directory/"restored-words.json");data=std::move(old);bundled=std::move(words);licenses=std::move(oldLicense);throw;}}
};
}
