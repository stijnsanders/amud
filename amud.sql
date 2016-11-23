create table Item (
ID integer primary key autoincrement,
ParentID integer null,
name varchar(200) not null,
what varchar(20) not null,
key varchar(200) null,
data text not null,
createdon datetime null,
createdby int null
);

insert into Item (name,what,data) values ('Sunburst Hotel Lobby','room','{}');
insert into Item (name,what,data,key) values ('Sunburst Hotel Hallway','room','{}','welcome:hall');

insert into Item (name,ParentID,what,data) values ('exit',(select ID from Item where name='Sunburst Hotel Hallway'),'door','{"to":'||(select ID from Item where name='Sunburst Hotel Lobby')||'}');
insert into Item (name,ParentID,what,data) values ('to the rooms',(select ID from Item where name='Sunburst Hotel Lobby'),'door','{"to":'||(select ID from Item where name='Sunburst Hotel Hallway')||'}');

insert into Item (name,ParentID,what,data) values ('',,'PowerTool','{}');
insert into Item (name,ParentID,what,data) values ('',,'RoomMaker','{}');
insert into Item (name,ParentID,what,data) values ('',,'NoteBloc','{left:50}');
insert into Item (name,ParentID,what,data) values ('2000000000 credits',,'money','{}');
