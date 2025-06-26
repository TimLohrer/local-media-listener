package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"runtime"
	"strings"
	"sync"
	"time"

	"github.com/godbus/dbus/v5"
)

type MediaInfo struct {
    Title     string `json:"title"`
    Artist    string `json:"artist"`
    Album     string `json:"album"`
    ImageURL  string `json:"imageUrl"`
    AppName   string `json:"appName"`
}

var (
    mu          sync.RWMutex
    currentInfo *MediaInfo
    subs        []chan *MediaInfo
)

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
        Title:     parts[0],
        Artist:    parts[1],
        Album:     parts[2],
        ImageURL:  parts[3],
        AppName:   parts[4],
    }
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
        title := metadata["xesam:title"].Value().(string)
        artistArr := metadata["xesam:artist"].Value().([]string)
        album := metadata["xesam:album"].Value().(string)
        artUrl := metadata["mpris:artUrl"].Value().(string)
        return &MediaInfo{
            Title:     title,
            Artist:    strings.Join(artistArr, ", "),
            Album:     album,
            ImageURL:  artUrl,
            AppName:   strings.TrimPrefix(name, "org.mpris.MediaPlayer2."),
        }
    }
    return nil
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
                return t & "|" & ar & "|" & al & "|" & artUrl & "|Spotify"
            end if
        end tell
    else if application "Music" is running then
        tell application "Music"
            if player state is playing then
                set t to name of current track
                set ar to artist of current track
                set al to album of current track
                return t & "|" & ar & "|" & al & "|null|Music"
            end if
        end tell
    end if
    '`
    out, err := exec.Command("bash", "-lc", script).Output()
    if err != nil {
        return nil
    }
    parts := strings.Split(strings.TrimSpace(string(out)), "|")
    if len(parts) < 4 {
        return nil
    }
    return &MediaInfo{
        Title:     parts[0],
        Artist:    parts[1],
        Album:     parts[2],
        ImageURL:  parts[3],
        AppName:   parts[4],
    }
}

func getNowPlaying() *MediaInfo {
    switch runtime.GOOS {
    case "windows":
        return fetchFromWindows()
    case "linux":
        return fetchFromLinux()
    case "darwin":
        return fetchFromMac()
    default:
        return nil
    }
}

func equal(a, b *MediaInfo) bool {
    if a == nil && b == nil {
        return true
    }
    if a == nil || b == nil {
        return false
    }
    return a.Title == b.Title && a.Artist == b.Artist && a.Album == b.Album && a.ImageURL == b.ImageURL
}

func pollLoop(interval time.Duration) {
    for {
        // print("Polling for media info...\n")
        time.Sleep(interval)
        info := getNowPlaying()
        mu.Lock()
        if !equal(info, currentInfo) {
            currentInfo = info
            for _, ch := range subs {
                go func(c chan *MediaInfo) {
                    c <- info
                }(ch)
            }
        }
        mu.Unlock()
    }
}

func main() {
    go pollLoop(1 * time.Second)

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
        flusher, ok := w.(http.Flusher)
        if !ok {
            http.Error(w, "Streaming unsupported", http.StatusInternalServerError)
            return
        }

        ch := make(chan *MediaInfo, 1)
        mu.Lock()
        subs = append(subs, ch)
        mu.Unlock()

        w.Header().Set("Content-Type", "text/event-stream")
        w.Header().Set("Cache-Control", "no-cache")
        w.Header().Set("Connection", "keep-alive")
        for {
            select {
            case info := <-ch:
                if info == nil {
                    w.Write([]byte("event:stop\n"))
                } else {
                    b, _ := json.Marshal(info)
                    w.Write([]byte("data:" + string(b) + "\n"))
                }
                flusher.Flush()
            case <-r.Context().Done():
                return
            }
        }
    })

    http.HandleFunc("/exit", func(w http.ResponseWriter, r *http.Request) {
        mu.Lock()
        for _, ch := range subs {
            close(ch)
        }
        subs = nil
        mu.Unlock()
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
