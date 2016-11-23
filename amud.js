var msg = document.getElementById("msg");
var constate = document.getElementById("constate");
var inventory = document.getElementById("inventory");
var room = document.getElementById("room");
var things = document.getElementById("things");
var persons = document.getElementById("persons");
var prompt = document.getElementById("prompt1");
try{

  if(!"WebSocket" in window){throw "Your browser doesn't support WebSocket";}
  if(!"localStorage" in window){throw "Your browser doesn't support localStorage";}
  if(!"textContent" in msg){throw "Your browser doesn't support textContent";}
  if(!"classList" in Element.prototype){throw "Your browser doesn't support classList";}

  var feed;//see below
  var sthing=null;

  function thingClick1(event){
    var n=event.target;
    n.classList.add("hot");
    n.onclick=thingClick2;
    feed.send("c"+n.parentElement.id.substr(5));//"thing..."
  }
  function thingClick2(event){
    var n=event.target;
    if(sthing)sthing.classList.remove("select");
    sthing=n;
    n.classList.add("select");
  }
  function personClick1(event){
    if(sthing){
      var n=event.target;
      n.classList.add("hot");
      //n.onclick=personClick2;
      feed.send("a"+n.parentElement.id.substr(6)+//"person..."
        (sthing?","+sthing.parentElement.id.substr(5):""));//"thing..."
    }
  }
  function cmdClick(event){
    var n=event.target;
    var d=document.getElementById("dixit"+n.parentElement.id.substr(5));//"thing"...
    if(d)d.textContent="";
    n.classList.add("hot");
    feed.send("d"+n.id.substr(3));//"cmd..."
    event.preventDefault();
  }
  function actClick(event){
    var n=event.target;
    n.classList.add("hot");
    feed.send("p"+n.id.substr(3));//"act"...
    event.preventDefault();
  }

  constate.textContent="Connecting...";
  feed=new WebSocket(function(){
    var x=document.location.href.split("/");
    x[0]="ws:";
    x[4]="feed";
    return x.join("/");
  }());
  feed.onopen=function(){
    var id=localStorage.getItem("aMUDid");
    if(id){
      constate.textContent="Authenticating...";
      feed.send("#"+id);
      room.textContent="...";
      room.classList.add("hot");
    }
    else
    {
      constate.style.display="none";
      room.textContent="Are you OK with this website using localStorage for a key to uniquely identify you?";
      room.insertAdjacentHTML('beforeEnd','<br /><span class="link">Yes</span>');
      room.onclick=function(){
        room.textContent="Requesting new person identification...";
        feed.send("n");
        room.classList.add("hot");
        room.onclick=null;
      };
    }
  };
  feed.onerror=function(e){
    constate.textContent=e;
    constate.style.display="";
  };
  feed.onclose=function(e){
    constate.textContent="Connection lost";
    constate.style.display="";
    //TODO: reconnect
  };
  feed.onmessage=function(xx){
    var x=xx.data.split("\x60");
    ({

      "#n":function(){//new UserID
        if(localStorage.getItem("aMUDid")){
          throw "Unexpected new UserID";
        }
        else{
          localStorage.setItem("aMUDid",x[1]);
        }
      },
      "#d":function(){//debug message
        constate.style.display="none";
        console.log(x[1]);
      },

      "r":function(){//enter room
        //room.xID=x[1];
        room.title=x[2];
        room.textContent=x[3];
        room.classList.remove("hot");
        things.textContent="";//clear things
        persons.textContent="";//clear persons
        msg.textContent="";
        if(sthing){
          sthing.classList.remove("select");
          sthing=null;
        }
        if(room.style.animation==""){
          room.style.animation="new 1s";
          window.setTimeout(function(){room.style.animation="";},1000);
        }
        var i=4;
        while(i<x.length){
          if(x[i]=="t"){
            var n=document.createElement("DIV");
            n.id="thing"+x[i+1];
            n.className="thing";
            var d=document.createElement("SPAN");
            d.title=x[i+2];
            d.textContent=x[i+2]+(x[i+3]?" \""+x[i+3]+"\"":"");
            d.onclick=thingClick1;
            n.append(d);
            things.append(n);
            i+=4;
          }
          else{
            throw "Unknown room thing type \""+x[i]+"\"";
          }
        }
      },
      "t+":function(){//thing in room
        if(!document.getElementById("thing"+x[1])){
          var n=document.createElement("DIV");
          n.id="thing"+x[1];
          n.className="thing";
          var d=document.createElement("SPAN");
          d.title=x[2];
          d.textContent=x[2]+(x[3]?" \""+x[3]+"\"":"");
          d.onclick=thingClick1;
          n.append(d);
          things.append(n);
          d.style.animation="new 1s";
          window.setTimeout(function(){d.style.animation="";},1000);
        }
      },
      "t-":function(){//thing gone from room
        var n=document.getElementById("thing"+x[1]);
        if(n)n.remove();
      },
      "r+":function(){//person enters
        var p=document.getElementById("person"+x[1]);
        if(p)p.remove();
        var n=document.createElement("DIV");
        n.id="person"+x[1];
        n.className="person";
        var d=document.createElement("SPAN");
        d.title=x[2];
        d.textContent=x[3];
        d.onclick=personClick1;
        n.append(d);
        persons.append(n);
        if(x[5]){
          var m=document.createElement("SPAN");
          m.className="personfrom";
          m.textContent=" \u2039 "+x[5]+(x[6]?" \""+x[6]+"\"":"");
          n.append(m);
          window.setTimeout(function(){m.remove();},3000);
          d.style.animation="new 1s";
          window.setTimeout(function(){d.style.animation="";},1000);
        }
      },
      "r-":function(){//user leaves
        var n=document.getElementById("person"+x[1]);
        if(n){
          n.textContent="("+x[2]+(x[3]?" \""+x[3]+"\"":"")+" took "+x[5]+(x[6]?" \""+x[6]+"\"":"")+")";
          n.classList.add("personleft");
          n.style.animation="new 1s";
          window.setTimeout(function(){n.remove();},5000);
        }
      },
      "i+":function(){//inventory add
        if(!document.getElementById("thing"+x[1])){
          var n=document.createElement("DIV");
          n.id="thing"+x[1];
          n.className="thing";
          var d=document.createElement("SPAN");
          d.title=x[2];
          d.textContent=x[2]+(x[3]?" \""+x[3]+"\"":"");
          d.onclick=thingClick1;
          n.append(d);
          inventory.append(n);
          d.style.animation="new 1s";
          window.setTimeout(function(){d.style.animation="";},1000);
        }
      },
      "i-":function(){//inventory gone
        var n=document.getElementById("thing"+x[1]);
        if(n){
          if(sthing==n.children[0])sthing=null;
          n.remove();
        }
      },
      "ii":function(){//inventory update
        var n=document.getElementById("thing"+x[1]);
        if(n){
          if(sthing==n.children[0])sthing=null;
          n.textContent="";//clear commands
        }else{
          n=document.createElement("DIV");
          n.id="thing"+x[1];
          n.className="thing";
          inventory.append(n);
        }
        var d=document.createElement("SPAN");
        d.onclick=thingClick1;
        d.title=x[2];
        d.textContent=x[2]+(x[3]?" \""+x[3]+"\"":"");
        n.append(d);
        if(d.style.animation==""){
          d.style.animation="new 1s";
          window.setTimeout(function(){d.style.animation="";},1000);
        }
      },
      "c":function(){//list commands
        var n=document.getElementById("thing"+x[1]);
        n.children[0].classList.remove("hot");
        n.insertAdjacentHTML("beforeEnd"," &rsaquo;");
        for(var i=2;i<x.length;i++){
          var c=document.createElement("SPAN");
          c.id="cmd"+x[1]+x[i];
          c.className="link";
          c.textContent=x[i];
          c.onclick=cmdClick;
          n.insertAdjacentHTML("beforeEnd"," ");
          n.append(c);
        }
      },
      "c.":function(){//command done
        var n=document.getElementById("cmd"+x[1]);
        if(n)n.classList.remove("hot");
      },
      "a":function(){//list actions
        var n=document.getElementById("person"+x[1]);
        n.children[0].classList.remove("hot");
        for(var i=2;i<x.length;i+=2){
          var c=document.createElement("SPAN");
          c.id="act"+x[1]+x[i]+x[i+1];
          c.className="link";
          c.textContent=x[i];
          c.onclick=actClick;
          n.insertAdjacentHTML("beforeEnd"," ");
          n.append(c);
        }
      },
      "a.":function(){//action done
        var n=document.getElementById("act"+x[1]);
        if(n){
          n=n.parentElement;
          var i=1;
          while(i<n.children.length)
            if(n.children[i].id.substr(0,3)=="act")
              n.children[i].remove();
            else
              i++;
        }
      },
      "s":function(){//say
        var n=document.getElementById("dixit"+x[1]);
        if(!n){
          var p=document.getElementById("person"+x[1]);
          n=document.createElement("SPAN");
          n.id="dixit"+x[1];
          n.className="dixit";
          p.insertAdjacentHTML("beforeEnd"," &rsaquo; ");
          p.append(n);
        }
        n.textContent=x[2];
        if(n.style.animation==""){
          n.style.animation="new 1s";
          window.setTimeout(function(){n.style.animation="";},1000);
        }
      },
      "m":function(){//message
        var n=document.getElementById("dixit"+x[1]);
        if(!n){
          var p=document.getElementById("thing"+x[1]);
          n=document.createElement("SPAN");
          n.id="dixit"+x[1];
          n.className="dixit";
          p.insertAdjacentHTML("beforeEnd"," &rsaquo; ");
          p.append(n);
        }
        n.textContent=x[2];
        if(n.style.animation==""){
          n.style.animation="new 1s";
          window.setTimeout(function(){n.style.animation="";},1000);
        }
      },
      "u":function(){//pop-up
        var n1=document.createElement("DIV");
        n1.id="info1";
        document.body.append(n1);
        var n2=document.createElement("DIV");
        n2.id="info2";
        document.body.append(n2);
        var n3=document.createElement("DIV");
        n3.id="info3";
        n3.textContent="Close";
        n3.onclick=n1.onclick=function(){
          n3.remove();
          n2.remove();
          n1.remove();
        };
        document.body.append(n3);
        var n4=document.createElement("IFRAME");
        n4.id="info4";
        n4.src=x[1];
        n2.append(n4);
      },

      "#":function(){msg.textContent=x[1];}//error
    }[x[0]]||function(){
      throw "unknown message command \""+x[0]+"\"";
    })();
  };
  document.onclick=function(){
    prompt.focus();
  }
  prompt.onkeypress=function(event){
    if(event.key=="Enter"){
      msg.textContent="";
      feed.send("s"+prompt.value);
      prompt.value="";
    }
  };
  prompt.focus();
}
catch(e){
  msg.style.display="";
  msg.textContent=e;
  msg.innerText=e;
  msg.style.color="red";
  console.log(e);
}
