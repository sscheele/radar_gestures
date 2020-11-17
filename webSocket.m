%server = EchoServer(30000);

%server.sendToAll('5');

%delete(server);
%clear server;