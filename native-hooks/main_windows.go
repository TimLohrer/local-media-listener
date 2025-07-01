//go:build windows
// +build windows

package main

/*
#include <stdint.h>
*/
import "C"
import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os/exec"
	"strings"
	"sync"
	"time"

	"github.com/gorilla/websocket" // Import the websocket library
)

type MediaInfo struct {
	Title    string `json:"title"`
	Artist   string `json:"artist"`
	Album    string `json:"album"`
	ImageURL string `json:"imageUrl"`
	Duration string `json:"duration"`
	Position string `json:"position"`
	AppName  string `json:"source"`
}

var (
	mu          sync.RWMutex
	currentInfo *MediaInfo
	httpServer  *http.Server
	wsClients   = make(map[*websocket.Conn]chan *MediaInfo)
	clientMux   sync.Mutex // Protects wsClients map
)

var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	CheckOrigin: func(r *http.Request) bool {
		return true
	},
}

func fetchFromWindows() *MediaInfo {
	cmd := exec.Command("./winmedia_helper.exe")
	out, err := cmd.Output()
	if err != nil {
		fmt.Println("Error executing winmedia_helper:", err)
		return nil
	}
	parts := strings.Split(strings.TrimSpace(string(out)), "|")
	if len(parts) < 5 {
		return nil
	}
	return &MediaInfo{
		Title:    parts[0],
		Artist:   parts[1],
		Album:    parts[2],
		ImageURL: parts[3],
		Duration: "null",
		Position: "null",
		AppName:  parts[4],
	}
}

func equal(a, b *MediaInfo) bool {
	if a == nil && b == nil {
		return true
	}
	if a == nil || b == nil {
		return false
	}
	return a.Title == b.Title && a.Artist == b.Artist && a.Album == b.Album && a.ImageURL == b.ImageURL && a.Duration == b.Duration && a.Position == b.Position && a.AppName == b.AppName
}

func pollLoop(interval time.Duration) {
	for {
		time.Sleep(interval)
		info := fetchFromWindows()
		mu.Lock()
		if !equal(info, currentInfo) {
			currentInfo = info
			// Notify all connected WebSocket clients
			clientMux.Lock()
			for _, ch := range wsClients {
				select {
				case ch <- info:
					// Sent successfully
				default:
					fmt.Println("Warning: WebSocket client channel is full, skipping update.")
				}
			}
			clientMux.Unlock()
		}
		mu.Unlock()
	}
}

//export Init
func Init() {
	go pollLoop(500 * time.Millisecond)

	mux := http.NewServeMux()

	mux.HandleFunc("/ready", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})

	mux.HandleFunc("/now-playing", func(w http.ResponseWriter, r *http.Request) {
		mu.RLock()
		defer mu.RUnlock()
		if currentInfo == nil {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(currentInfo)
	})

	mux.HandleFunc("/now-playing/subscribe", func(w http.ResponseWriter, r *http.Request) {
		conn, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
			fmt.Println("WebSocket upgrade error:", err)
			return
		}
		defer conn.Close()

		clientChan := make(chan *MediaInfo, 5)

		clientMux.Lock()
		wsClients[conn] = clientChan
		clientMux.Unlock()

		fmt.Println("New WebSocket client connected.")

		mu.RLock()
		if currentInfo != nil {
			if err := conn.WriteJSON(currentInfo); err != nil {
				fmt.Println("Error sending initial info to WebSocket client:", err)
			}
		}
		mu.RUnlock()

		go func() {
			for {
				_, _, err := conn.ReadMessage()
				if err != nil {
					// Client disconnected or error occurred
					fmt.Println("WebSocket client disconnected or error:", err)
					break // Exit the read loop
				}
			}

			clientMux.Lock()
			delete(wsClients, conn)
			close(clientChan)
			wsClients = make(map[*websocket.Conn]chan *MediaInfo)
			clientMux.Unlock()
			fmt.Println("WebSocket client disconnected.")
		}()

		// Loop to send updates to the client
		for {
			select {
			case info, ok := <-clientChan:
				if !ok {
					return
				}
				if info == nil {
					if err := conn.WriteJSON(map[string]string{"event": "stopped"}); err != nil {
						fmt.Println("Error sending stop message to WebSocket client:", err)
						return
					}
				} else {
					if err := conn.WriteJSON(info); err != nil {
						fmt.Println("Error sending media info to WebSocket client:", err)
						return
					}
				}
			}
		}
	})

	mux.HandleFunc("/control/play-pause", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}
		//if playPause() {
		//	w.WriteHeader(http.StatusOK)
		//} else {
		//	http.Error(w, "Failed to toggle play/pause", http.StatusInternalServerError)
		//	return
		//}
		http.Error(w, "Play/Pause control not implemented", http.StatusNotImplemented)
	})

	mux.HandleFunc("/control/next", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}
		//if next() {
		//	w.WriteHeader(http.StatusOK)
		//} else {
		//	http.Error(w, "Failed to skip to next track", http.StatusInternalServerError)
		//	return
		//}
		http.Error(w, "Next control not implemented", http.StatusNotImplemented)
	})

	mux.HandleFunc("/control/back", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}
		//if back() {
		//	w.WriteHeader(http.StatusOK)
		//} else {
		//	http.Error(w, "Failed to skip to previous track", http.StatusInternalServerError)
		//	return
		//}
		http.Error(w, "Back control not implemented", http.StatusNotImplemented)
	})

	httpServer = &http.Server{
		Addr:    "127.0.0.1:14565",
		Handler: mux,
	}

	go func() {
		fmt.Println("OS Media daemon listening on http://localhost:14565")
		if err := httpServer.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			fmt.Println("HTTP server error:", err)
		}
	}()
}

//export Shutdown
func Shutdown() {
	fmt.Println("Shutting down HTTP server...")

	if httpServer != nil {
		ctx, cancel := context.WithTimeout(context.Background(), 1*time.Second)
		defer cancel()
		if err := httpServer.Shutdown(ctx); err != nil {
			fmt.Println("Error during server shutdown:", err)
		} else {
			fmt.Println("HTTP server shut down cleanly.")
		}
		httpServer = nil
	}

	fmt.Println("Shutdown complete.")
}

func main() {}
