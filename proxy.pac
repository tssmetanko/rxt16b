function FindProxyForURL(url,host) {
    var torProxy = 'SOCKS5 127.0.0.1:9050';
    var httpProxy = 'HTTP 69.25.112.155:35002';
    var proxyViaTOR = ['*.telegram.org','telegram.org','*.lurkmore.to','*.linkedin.com','linkedin.com',"*pleer.com","*rutracker.org","app.terraform.io","*.meduza.io","meduza.io"];
    var proxyViaHttp = ['music.youtube.com','play.google.com', '*.googlevideo.com', 'googlevideo.com' ]
    
    for (var i=0; i< proxyViaTOR.length; i++){
      if (shExpMatch(host,proxyViaTOR[i])){
        return torProxy;
      }
    }
    
    for (var y=0; y< proxyViaHttp.length; y++){
      if (shExpMatch(host,proxyViaHttp[y])){
        return httpProxy;
      }
    }
    return "DIRECT";
}