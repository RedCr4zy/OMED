#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Serveur Python WebSocket pour le projet OMED.
Permet une communication bidirectionnelle temps réel entre l'application Flutter et le serveur.
"""

import asyncio
import websockets

async def handle_client(websocket):
    print("Client connecté")
    try:
        await websocket.send("Connection réussie pour client -> serveur !")

        async for message in websocket:
            print("Message reçu: ", message)

            await websocket.send("Message reçu !")

    except websockets.exceptions.ConnectionClosed:
        print("Client déconnecté")

async def main():
    async with websockets.serve(handle_client, "127.0.0.1", 8765):
        print("Serveur WebSocket en écoute sur ws://localhost:8765")
        await asyncio.Future()

asyncio.run(main())

