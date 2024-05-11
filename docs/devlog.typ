= Build your own Redis (Zig version)

== Intro

=== Bind to a port

Looks like standard stuff for port binding. 
*DON'T FORGET `try`!!!!*

=== Respond to PING

==== Task

In this stage, you'll implement support for the *PING* command.

Redis clients communicate with Redis servers by sending `commands`.
For each command, a Redis server sends a response back to the client.
Commands and responses are both encoded using the `Redis protocol`

*PING* is one of the simplest Redis commands. It's used to check whether Redis server is healthy.

The response for the `PING` command is `+PONG\r\n`. This is the string "PONG" encoded using the `Redis protocol`.

In this stage, we'll cut corners by ignoring client input and hardcoding `+PONG\r\n` as a response.
We'll learn to parse client input in later stages.

==== Tests

The tester will execute your program like this:
```sh
./spawn_redis_server.sh
```

It'll send a `PING` command to your server and expect a `+PONG\r\n` response.
```sh
redis-cli PING
```

==== Notes

- You can ignore the data that the tester sends you for this stage.

  We'll be parsing client input in later stages. For now, you can just hardcode `+PONG\r\n` as the response.

- You can also ignore handling multiple clients and handling multiple PING commands in the stage, we'll get to that in later stages.

- The exact bytes your program will receive won't just be PING, you'll receive something like this:`*1\r\n$4\r\nPING\r\n`, which is  the Redis protocol encoding of the PING command. We'll learn more about this in later stages.

=== Respond to multiple PINGs

==== Task
In this stage, we'll respond to multiple `PING` commands sent by the same connection.

A Redis server starts to listen for the next command as soon as it's done responding to the previous one.
This allows Redis clients to send multiple commands using the same connection.

==== Tests

The tester will execute your program like so:
``sh
./spawn_redis_server.sh
``

It'll then send 2 PING commands using the same connection:
``sh
echo -e "PING\n\PING" | redis-cli
``

The test will expect to receive 2 `+PONG\r\n` responses.

We'll need to run a loop that reads inputs from a connection and sends a response back.

==== Notes

- Just like the previous stage, we can hardcode `+PONG\r\n` as the response of this stage. We'll get to parsing input in later stages.

- The 2 PING commands will be sent using the same connection. We'll get to handling multiple connections in later stages.

=== Handle concurrent clients

==== Task

In this stage, we'll add support for multiple concurrent clients.

In addition to handling multiple commands from the same client, Redis servers are also designed to handle multiple clients at once.

To implement this, we'll need to either use threads, or an event loop, like the official Redies implementation does.

==== Tests

The server will execute your program like this:
``sh
./spawn_redis_server.sh
``

It'll then send 2 PING commands conncurrently using 2 different connections:
``sh
// These two will be sent concurrently so that we test your server's ability to handle concurrent clients.
redis-cli PING
redis-cli PING
``

The tester will expect to receive 2 `+PONG\r\n` responses.

==== Notes

Since the tester client _only_ sends the PING command at the moment, it's okay to ignore what the client sends and hardcode a response. We'll get to parsing client input in later stages.