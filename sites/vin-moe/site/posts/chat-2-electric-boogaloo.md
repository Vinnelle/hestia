---
title: Chat 2 electric boogaloo
date: 2026-10-02
draft: false
---

What is up party peepol,

This chat thing has TAKEN OVER MY LIFE

I have spent so much time working on this it has changed so much.

I am now on v0.1.12, I personally feel like it has improved massively.

Here is a screenshot:
![image](https://blog.vin.moe/media/image-c093ac9c.png)
It now supports Tor routing as well as DHT routing. I am using Nostr nodes as a bridge between the two so Tor users can still talk to DHT users. Nostr also helps users under CGNATs connect to the service, as this was an issue before with pure DHT routing.

To the limits of my technical ability and knowledge, this should be very difficult, at the very least, to track, sniff, de-anonymise, or know of, users using chat.

I am working on a name still, I think chat is too generic to ever catch on, and, on the AUR at least, whilst there is no 'chat' package, 'ppp' installed /bin/chat, which is frustrating.

You preferably wouldn't install this anyway, since that sort of defeats the purpose, so I suggest that users simply place the chat binary in their .local bin. 

I have also set up an :install command that saves the users configuration. This is encrypted, obviously, so it should still, technically, be secure. If I wanted to push it further, I would probably obfuscate the save file location, but that is security via obscurity, and likely unnecessary.

Anyway, thats what I am doing, thanks for reading.

BYE
