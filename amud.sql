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

--add these for the first user:
insert into Item (name,ParentID,what,data) values ('',,'PowerTool','{}');
insert into Item (name,ParentID,what,data) values ('',,'RoomMaker','{}');
insert into Item (name,ParentID,what,data) values ('',,'LockMaker','{}');
insert into Item (name,ParentID,what,data) values ('',,'NoteBloc','{"left":50}');
insert into Item (name,ParentID,what,data) values ('2000000000 credits',,'money','{}');

--add this to 'City Hall, registry office'
insert into Item (name,ParentID,what,data) values ('Citizen Registration Form',,'form','{"form":"Reg"}');

create table User (
ID integer primary key,
FirstName varchar(100) not null,
LastName varchar(100) not null,
EmailAddress varchar(100) not null,
Comment text not null,
createdon datetime not null,
constraint FK_User_Item foreign key (ID) references Item (ID)
);

create table Bot (
ID integer primary key autoincrement,
ItemID integer not null,
RoomID integer not null,
Script varchar(50) not null,
constraint FK_Bot_Item foreign key (ItemID) references Item (ID),
constraint FK_Bot_Room foreign key (RoomID) references Item (ID)
);

insert into Item(name,what,data) values ('Eliza Weisenbaum','psychotherapist','{}');
insert into Bot(ItemID,RoomID,Script) values (,,'eliza');

insert into Item (name,what,data) values ('receptionist','receptionist','{}');
insert into Bot(ItemID,RoomID,Script) values (,,'receptionist');


