//go:build darwin
// +build darwin

package main

/*
#include <stdint.h>
*/
import "C"
import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
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

func fetchFromMac() *MediaInfo {
	script := `osascript -e '
    if application "Spotify" is running then
        tell application "Spotify"
            if player state is playing then
                set t to name of current track
                set ar to artist of current track
                set al to album of current track
                set artUrl to artwork url of current track
				try
                    set dur to (duration of current track as string)
                on error
                    set dur to "null"
                end try

                try
                    -- Player position is a property of the application, not the track
                    set pos to (player position of application "Spotify" as string)
                on error
                    set pos to "null"
                end try
                return t & "|" & ar & "|" & al & "|" & artUrl & "|" & dur & "|" & pos & "|Spotify"
            end if
        end tell
    else if application "Music" is running then
        tell application "Music"
            if player state is playing then
                set t to name of current track
                set ar to artist of current track
                set al to album of current track
				try
					set artUrl to artwork url of current track
				on error
					set artUrl to "null"
				end try
				try
                    set dur to (duration of current track as string)
                on error
                    set dur to "null"
                end try

                try
                    -- Player position is a property of the application, not the track
                    set pos to (player position of application "Music" as string)
                on error
                    set pos to "null"
                end try
                return t & "|" & ar & "|" & al & "|" & artUrl & "|" & dur & "|" & pos & "|AppleMusic"
            end if
        end tell
    end if
    '`
	out, err := exec.Command("bash", "-lc", script).Output()
	if err != nil {
		return nil
	}
	parts := strings.Split(strings.TrimSpace(string(out)), "|")
	if len(parts) < 7 {
		return nil
	}
	return &MediaInfo{
		Title:    parts[0],
		Artist:   parts[1],
		Album:    parts[2],
		ImageURL: parts[3],
		Duration: parts[4],
		Position: parts[5],
		AppName:  parts[6],
	}
}

func back() bool {
	script := `osascript -e '
	if application "Spotify" is running then
		tell application "Spotify" to previous track
	else if application "Music" is running then
		tell application "Music" to previous track
	end if
	'`
	_, err := exec.Command("bash", "-lc", script).Output()
	if err != nil {
		fmt.Println("Error executing back command:", err)
		return false
	}
	return true
}

func next() bool {
	script := `osascript -e '
	if application "Spotify" is running then
		tell application "Spotify" to next track
	else if application "Music" is running then
		tell application "Music" to next track
	end if
	'`
	_, err := exec.Command("bash", "-lc", script).Output()
	if err != nil {
		fmt.Println("Error executing next command:", err)
		return false
	}
	return true
}

func playPause() bool {
	script := `osascript -e '
	if application "Spotify" is running then
		tell application "Spotify" to playpause
	else if application "Music" is running then
		tell application "Music" to playpause
	end if
	'`
	_, err := exec.Command("bash", "-lc", script).Output()
	if err != nil {
		fmt.Println("Error executing play/pause command:", err)
		return false
	}
	return true
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
		info := fetchFromMac()
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

	http.HandleFunc("/ready", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})

	http.HandleFunc("/now-playing", func(w http.ResponseWriter, r *http.Request) {
		mu.RLock()
		defer mu.RUnlock()
		if currentInfo == nil {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(currentInfo)
	})

	http.HandleFunc("/now-playing/subscribe", func(w http.ResponseWriter, r *http.Request) {
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

	http.HandleFunc("/control/play-pause", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}
		if playPause() {
			w.WriteHeader(http.StatusOK)
		} else {
			http.Error(w, "Failed to toggle play/pause", http.StatusInternalServerError)
			return
		}
	})

	http.HandleFunc("/control/next", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}
		if next() {
			w.WriteHeader(http.StatusOK)
		} else {
			http.Error(w, "Failed to skip to next track", http.StatusInternalServerError)
			return
		}
	})

	http.HandleFunc("/control/back", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}
		if back() {
			w.WriteHeader(http.StatusOK)
		} else {
			http.Error(w, "Failed to skip to previous track", http.StatusInternalServerError)
			return
		}
	})

	http.HandleFunc("/exit", func(w http.ResponseWriter, r *http.Request) {
		clientMux.Lock()
		for conn, ch := range wsClients {
			conn.WriteMessage(websocket.CloseMessage, websocket.FormatCloseMessage(websocket.CloseNormalClosure, "Server exiting"))
			conn.Close()
			close(ch)
		}
		wsClients = make(map[*websocket.Conn]chan *MediaInfo) // Clear the map
		clientMux.Unlock()

		w.WriteHeader(http.StatusOK)
		fmt.Fprintln(w, "Exiting...")
		os.Exit(0)
	})

	port := "14565"
	fmt.Printf("OS Media daemon listening on http://localhost:%s\n", port)
	if err := http.ListenAndServe("127.0.0.1:"+port, nil); err != nil {
		fmt.Println("Error:", err)
		os.Exit(1)
	}
}

func main() {}
