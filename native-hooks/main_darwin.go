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
	"io"
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

type Application struct {
	AppName     string
	DisplayName string
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

var supportedApplications = []Application{
	// Media Players
	{AppName: "Spotify", DisplayName: "Spotify"},
	{AppName: "Music", DisplayName: "Apple Music"}, // Native Music app
	//{AppName: "VLC", DisplayName: "VLC Media Player"},

	// Browsers - Disabled for performance reasons
	//{AppName: "Safari", DisplayName: "Safari"},
	//{AppName: "Google Chrome", DisplayName: "Google Chrome"},
	//{AppName: "Firefox", DisplayName: "Mozilla Firefox"},
	//{AppName: "Brave Browser", DisplayName: "Brave"},
	//{AppName: "Arc", DisplayName: "Arc Browser"},
	//{AppName: "Opera", DisplayName: "Opera"},
}

func getAppNameFromDisplayName(appName string) string {
	var result = ""
	for _, app := range supportedApplications {
		if app.DisplayName == appName {
			result = app.AppName
		}
	}
	return result
}

func fetchFromMac(appName string, displayName string) *MediaInfo {
	script := fmt.Sprintf(`osascript -e '
	if application "%s" is running then
		tell application "%s"
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
					set pos to (player position as string)
				on error
					set pos to "null"
				end try
	
				return t & "|" & ar & "|" & al & "|" & artUrl & "|" & dur & "|" & pos
			end if
		end tell
	end if
	'`, appName, appName)
	out, err := exec.Command("bash", "-lc", script).Output()
	if err != nil {
		return nil
	}
	parts := strings.Split(strings.TrimSpace(string(out)), "|")
	if len(parts) < 6 {
		return nil
	}
	return &MediaInfo{
		Title:    parts[0],
		Artist:   parts[1],
		Album:    parts[2],
		ImageURL: parts[3],
		Duration: parts[4],
		Position: parts[5],
		AppName:  displayName,
	}
}

func back(appName string) bool {
	script := fmt.Sprintf(`osascript -e '
	if application "%s" is running then
		tell application "%s" to previous track
	end if
	'`, appName, appName)
	_, err := exec.Command("bash", "-lc", script).Output()
	if err != nil {
		fmt.Println("Error executing back command:", err)
		return false
	}
	return true
}

func next(appName string) bool {
	script := fmt.Sprintf(`osascript -e '
		if application "%s" is running then
			tell application "%s" to next track
		end if
	'`, appName, appName)

	_, err := exec.Command("bash", "-lc", script).Output()
	if err != nil {
		fmt.Println("Error executing next command:", err)
		return false
	}
	return true
}

func playPause(appName string) bool {
	script := fmt.Sprintf(`osascript -e '
	if application "%s" is running then
		tell application "%s" to playpause
	end if
	'`, appName, appName)
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
		for _, app := range supportedApplications {
			var info = fetchFromMac(app.AppName, app.DisplayName)
			if info != nil {
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

		defer func(Body io.ReadCloser) {
			err := Body.Close()
			if err != nil {
				w.WriteHeader(http.StatusInternalServerError)
				return
			}
		}(r.Body)
		bodyBytes, err := io.ReadAll(r.Body)
		if err != nil {
			http.Error(w, "Failed to read body", http.StatusInternalServerError)
			return
		}

		bodyStr := string(bodyBytes)
		if playPause(getAppNameFromDisplayName(bodyStr)) {
			w.WriteHeader(http.StatusOK)
		} else {
			w.WriteHeader(http.StatusInternalServerError)
		}
	})

	http.HandleFunc("/control/next", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}

		defer func(Body io.ReadCloser) {
			err := Body.Close()
			if err != nil {
				w.WriteHeader(http.StatusInternalServerError)
				return
			}
		}(r.Body)
		bodyBytes, err := io.ReadAll(r.Body)
		if err != nil {
			http.Error(w, "Failed to read body", http.StatusInternalServerError)
			return
		}

		bodyStr := string(bodyBytes)
		if next(getAppNameFromDisplayName(bodyStr)) {
			w.WriteHeader(http.StatusOK)
		} else {
			w.WriteHeader(http.StatusInternalServerError)
		}
	})

	http.HandleFunc("/control/back", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}

		defer func(Body io.ReadCloser) {
			err := Body.Close()
			if err != nil {
				w.WriteHeader(http.StatusInternalServerError)
				return
			}
		}(r.Body)
		bodyBytes, err := io.ReadAll(r.Body)
		if err != nil {
			http.Error(w, "Failed to read body", http.StatusInternalServerError)
			return
		}

		bodyStr := string(bodyBytes)
		if back(getAppNameFromDisplayName(bodyStr)) {
			w.WriteHeader(http.StatusOK)
		} else {
			w.WriteHeader(http.StatusInternalServerError)
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
