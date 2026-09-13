#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Serveur Python WebSocket pour le projet OMED.
Permet une communication bidirectionnelle temps réel entre l'application Flutter et le serveur.
"""

import asyncio
import sys
import websockets

# Ensemble des clients connectés (application Flutter)
connected_clients = set()

async def handler(websocket):
    """Gère une connexion WebSocket entrante depuis l'application Flutter."""
    client_ip = websocket.remote_address
    print(f"\n[+] Nouvelle connexion établie avec l'application : {client_ip}")
    connected_clients.add(websocket)
    
    try:
        # Message de bienvenue envoyé à l'application
        await websocket.send("Connexion établie avec le serveur OMED avec succès !")
        
        async for message in websocket:
            print(f"\n[Reçu de l'App] : {message}")
            # Optionnel : écho ou traitement du message reçu
            # Ici on confirme la réception au client
            await websocket.send(f"Serveur a bien reçu : {message}")
            
    websockets.exceptions.ConnectionClosedOK:
        print(f"\n[-] Connexion fermée normalement par l'application : {client_ip}")
    websockets.exceptions.ConnectionClosedError as e:
        print(f"\n[!] Connexion interrompue avec {client_ip} : {e}")
    except Exception as e:
        print(f"\n[Erreur] Exception avec {client_ip} : {e}")
    finally:
        connected_clients.remove(websocket)
        print(f"[-] Application déconnectée : {client_ip}. Clients actifs : {len(connected_clients)}")

async def console_input_loop():
    """Permet à l'utilisateur d'entrer un message dans le terminal pour l'envoyer à l'application."""
    loop = asyncio.get_running_loop()
    print("[*] Console serveur prête. Tapez un message et appuyez sur Entrée pour l'envoyer à l'application :")
    
    while True:
        try:
            # Lecture asynchrone de l'entrée standard (terminal)
            message = await loop.run_in_executor(None, sys.stdin.readline)
            message = message.strip()
            
            if not message:
                continue
                
            print(f"[Envoyé vers l'App] : {message}")
            
            if not connected_clients:
                print("[!] Aucun client Flutter connecté actuellement.")
                continue
                
            # Diffusion du message à tous les clients connectés
            disconnected = set()
            for client in connected_clients:
                try:
                    await client.send(message)
                except websockets.exceptions.ConnectionClosed:
                    disconnected.add(client)
                except Exception as e:
                    print(f"[Erreur d'envoi] {e}")
                    disconnected.add(client)
            
            # Nettoyage des clients déconnectés
            for client in disconnected:
                connected_clients.remove(client)
                
        except (KeyboardInterrupt, asyncio.CancelledError):
            break
        except Exception as e:
            print(f"[Erreur console] {e}")

async def main():
    HOST = "0.0.0.0"
    PORT = 8765
    
    print("=" * 60)
    print(f"       SERVEUR PYTHON OMED - WEBSOCKET")
    print("=" * 60)
    print(f"[*] Démarrage du serveur sur ws://{HOST}:{PORT}")
    print(f"[*] Pour tester localement depuis Flutter, utilisez :")
    print(f"    - ws://10.0.2.2:{PORT} (si Émulateur Android)")
    print(f"    - ws://127.0.0.1:{PORT} (si Bureau Linux / Navigateur)")
    print("=" * 60)
    
    async with websockets.serve(handler, HOST, PORT):
        # Lancement simultané du serveur WebSocket et de la boucle de lecture console
        await console_input_loop()

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\n[*] Arrêt du serveur OMED par l'utilisateur.")
