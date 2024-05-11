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