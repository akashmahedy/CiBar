import Foundation
let destination=URL(fileURLWithPath:CommandLine.arguments[1])
if CommandLine.arguments.count > 2 {
    var decoded=try JSONDecoder().decode(Backup.self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[2])))
    guard decoded.format=="CiBarBackup",decoded.version==1,decoded.data.settings.selectionKey=="hsk2025|1:1-300,4:1-1000|false|false",decoded.data.sessions[decoded.data.settings.selectionKey]?.remaining==17.5,decoded.data.customWords.first?.example?.pinyin=="Nǐ hǎo." else { fatalError("Windows backup incompatible with Mac model") }
    try decoded.data.settings.validate()
    try Store.validateWords(decoded.words)
    try Store.writeBackup(decoded,to:destination)
    print("Windows → actual Mac Codable model → backup passed")
} else {
    var data=SavedData()
    data.settings.levels=[1,4]
    data.settings.ranges=["1":WordRange(start:1,end:300),"4":WordRange(start:1,end:1000)]
    let words=[Word(id:"hsk2025:1",pack:"hsk2025",level:1,serial:1,hanzi:"爱",pinyin:"ài",english:"love",source:"Contract fixture",note:"",example:nil),Word(id:"hsk2025:1001",pack:"hsk2025",level:4,serial:1,hanzi:"阿姨",pinyin:"āyí",english:"aunt",source:"Contract fixture",note:"",example:nil)]
    data.customWords=[Word(id:"custom-test:1",pack:"custom-test",level:0,serial:1,hanzi:"你好",pinyin:"nǐ hǎo",english:"hello",source:"Contract fixture",note:"",example:Example(hanzi:"你好。",pinyin:"Nǐ hǎo.",english:"Hello.",attribution:"Test fixture",sourceURL:"",pinyinAutomatic:false))]
    data.favorites=["hsk2025:1001"]
    data.sessions[data.settings.selectionKey]=Snapshot(order:words.map(\.id),index:1,remaining:17.5,manuallyPaused:true)
    let backup=Backup(data:data,words:words,licenses:"Synthetic test fixture. No private data.")
    try Store.writeBackup(backup,to:destination)
    print("Actual Mac model exported synthetic fixture")
}
