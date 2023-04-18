PRAGMA foreign_keys=OFF;
BEGIN TRANSACTION;
INSERT OR REPLACE INTO trees VALUES('lYTJe','Another doc, with title','cardbased','cypress@testing.com','[]',NULL,0,1680552170346,NULL);
INSERT OR REPLACE INTO trees VALUES('CJoWu',NULL,'cardbased','cypress@testing.com','[]',NULL,0,1680552130586,NULL);
INSERT OR REPLACE INTO cards VALUES('lYTJe:1','lYTJe','Another Test doc',NULL,0.0,'1607259392554:0:a52ea24a',0);
INSERT OR REPLACE INTO cards VALUES('lYTJe:node-1628744388','lYTJe',replace('# 2\nChild card','\n',char(10)),'lYTJe:1',0.0,'1607259392554:1:67a32294',0);
INSERT OR REPLACE INTO cards VALUES('lYTJe:node-230512886','lYTJe',replace('# 3\nAnother Child card','\n',char(10)),'lYTJe:1',1.0,'1607259392554:1:d3717110',0);
INSERT OR REPLACE INTO cards VALUES('CJoWu:1','CJoWu','Hello Test doc',NULL,0.0,'1607259388270:0:a8eb430c',0);
INSERT OR REPLACE INTO cards VALUES('CJoWu:node-1615554785','CJoWu','Child card','CJoWu:1',0.0,'1607259388270:1:b0eccef2',0);
INSERT OR REPLACE INTO cards VALUES('CJoWu:node-132318239','CJoWu','Another Child card','CJoWu:1',1.0,'1607259388270:1:ca65368d',0);
INSERT OR REPLACE INTO users VALUES('cypress@testing.com','d7cc8db0933d61b20591d84282fb4b2a','012e1e75f464154411db4f1a3e6fded149e0c30e',unixepoch()*1000,unixepoch()*1000,'trial:' || CAST(unixepoch()+ 14*24*60*60)*1000 AS TEXT),'en');
COMMIT;
