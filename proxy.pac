function FindProxyForURL(url,host) {
    var torProxy = 'SOCKS5 127.0.0.1:9050';
    var proxyViaTOR = ['*.telegram.org','telegram.org','*.lurkmore.to','*.linkedin.com','linkedin.com',"*pleer.com", "*rutracker.org"];
    
    for (var i=0; i< proxyViaTOR.length; i++){
      if (shExpMatch(host,proxyViaTOR[i])){
        return torProxy;
      }
    }
    return "DIRECT";
    
}
