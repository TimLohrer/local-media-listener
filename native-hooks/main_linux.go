//go:build linux
// +build linux

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
	"strings"
	"sync"
	"time"

	"github.com/godbus/dbus/v5"
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

func fetchFromLinux() *MediaInfo {
	conn, err := dbus.SessionBus()
	if err != nil {
		return nil
	}
	var names []string
	obj := conn.Object("org.freedesktop.DBus", "/org/freedesktop/DBus")
	err = obj.Call("org.freedesktop.DBus.ListNames", 0).Store(&names)
	if err != nil {
		return nil
	}
	for _, name := range names {
		if !strings.HasPrefix(name, "org.mpris.MediaPlayer2.") {
			continue
		}
		player := conn.Object(name, "/org/mpris/MediaPlayer2")
		var status string
		err = player.Call("org.freedesktop.DBus.Properties.Get", 0,
			"org.mpris.MediaPlayer2.Player", "PlaybackStatus").Store(&status)
		if err != nil || status != "Playing" {
			continue
		}
		var metadata map[string]dbus.Variant
		err = player.Call("org.freedesktop.DBus.Properties.Get", 0,
			"org.mpris.MediaPlayer2.Player", "Metadata").Store(&metadata)
		if err != nil {
			continue
		}
		var title, album, artistsArr, artUrl, durationStr, positionStr string
		if v, ok := metadata["xesam:title"]; !ok || v.Value() != nil {
			title = fmt.Sprintf("%v", v.Value())
		} else {
			title = "null"
		}

		if v, ok := metadata["xesam:album"]; ok && v.Value() != nil {
			album = fmt.Sprintf("%v", v.Value())
		} else {
			album = "null"
		}

		if v, ok := metadata["xesam:artist"]; !ok || v.Value() != nil {
			artistsArr = fmt.Sprintf("%v", strings.Join(v.Value().([]string), ", "))
		} else {
			artistsArr = "null"
		}

		if v, ok := metadata["mpris:artUrl"]; !ok || v.Value() != nil {
			artUrl = fmt.Sprintf("%v", v.Value())
		} else {
			artUrl = "null"
		}

		if v, ok := metadata["mpris:length"]; ok && v.Value() != nil {
			// Convert duration from microseconds to seconds
			if length, ok := v.Value().(int64); ok {
				durationStr = fmt.Sprintf("%.2f", float64(length)/1000000.0)
			} else {
				durationStr = fmt.Sprintf("%v", v.Value())
			}
		} else {
			durationStr = "null"
		}

		// Get Position
		var position int64
		err = player.Call("org.freedesktop.DBus.Properties.Get", 0,
			"org.mpris.MediaPlayer2.Player", "Position").Store(&position)
		if err == nil {
			positionStr = fmt.Sprintf("%.2f", float64(position)/1000000.0)
		} else {
			positionStr = "null"
		}

		return &MediaInfo{
			Title:    title,
			Artist:   artistsArr,
			Album:    album,
			ImageURL: artUrl,
			Duration: durationStr,
			Position: positionStr,
			AppName:  strings.TrimPrefix(name, "org.mpris.MediaPlayer2."),
		}
	}
	return nil
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
		info := fetchFromLinux()
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
