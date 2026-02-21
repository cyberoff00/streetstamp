package main

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"mime/multipart"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

const (
	visibilityPrivate     = "private"
	visibilityFriendsOnly = "friendsOnly"
	visibilityPublic      = "public"
)

type server struct {
	store    *store
	jwt      *jwtSigner
	mediaDir string
	mediaURL string
	r2       *r2Store
}

type r2Store struct {
	accessKeyID string
	secretKey   string
	bucket      string
	publicBase  string
	endpoint    string
	region      string
}

type store struct {
	mu   sync.RWMutex
	path string
	data db
}

type db struct {
	Users       map[string]*userRecord `json:"users"`
	EmailIndex  map[string]string      `json:"emailIndex"`
	InviteIndex map[string]string      `json:"inviteIndex"`
	OAuthIndex  map[string]string      `json:"oauthIndex"`
}

type userRecord struct {
	ID           string          `json:"id"`
	Provider     string          `json:"provider"`
	Email        string          `json:"email,omitempty"`
	PasswordHash string          `json:"passwordHash,omitempty"`
	InviteCode   string          `json:"inviteCode"`
	DisplayName  string          `json:"displayName"`
	Bio          string          `json:"bio"`
	Loadout      map[string]any  `json:"loadout,omitempty"`
	Journeys     []journeyRecord `json:"journeys,omitempty"`
	CityCards    []cityCard      `json:"unlockedCityCards,omitempty"`
	FriendIDs    []string        `json:"friendIDs,omitempty"`
	CreatedAt    int64           `json:"createdAt"`
}

type journeyRecord struct {
	ID          string         `json:"id"`
	Title       string         `json:"title"`
	ActivityTag string         `json:"activityTag,omitempty"`
	Overall     string         `json:"overallMemory,omitempty"`
	Distance    float64        `json:"distance"`
	StartTime   *time.Time     `json:"startTime,omitempty"`
	EndTime     *time.Time     `json:"endTime,omitempty"`
	Visibility  string         `json:"visibility"`
	Memories    []memoryRecord `json:"memories,omitempty"`
}

type memoryRecord struct {
	ID        string    `json:"id"`
	Title     string    `json:"title"`
	Notes     string    `json:"notes,omitempty"`
	Timestamp time.Time `json:"timestamp"`
	ImageURLs []string  `json:"imageURLs,omitempty"`
}

type cityCard struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	CountryISO2 string `json:"countryISO2,omitempty"`
}

type jwtSigner struct {
	secret []byte
}

type tokenClaims struct {
	UID string `json:"uid"`
	Prv string `json:"prv"`
	Typ string `json:"typ"`
	Exp int64  `json:"exp"`
	Iat int64  `json:"iat"`
}

type authResp struct {
	UserID       string  `json:"userId"`
	Provider     string  `json:"provider"`
	Email        *string `json:"email,omitempty"`
	AccessToken  string  `json:"accessToken"`
	RefreshToken string  `json:"refreshToken"`
}

type serverError struct {
	Message string `json:"message"`
}

type emailAuthReq struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

type oauthReq struct {
	Provider string `json:"provider"`
	IDToken  string `json:"idToken"`
}

type addFriendReq struct {
	DisplayName string  `json:"displayName"`
	InviteCode  *string `json:"inviteCode"`
}

type migrateReq struct {
	Journeys          []journeyRecord `json:"journeys"`
	UnlockedCityCards []cityCard      `json:"unlockedCityCards"`
}

type friendDTO struct {
	ID                string          `json:"id"`
	InviteCode        string          `json:"inviteCode,omitempty"`
	DisplayName       string          `json:"displayName"`
	Bio               string          `json:"bio,omitempty"`
	Loadout           map[string]any  `json:"loadout,omitempty"`
	Journeys          []journeyRecord `json:"journeys,omitempty"`
	UnlockedCityCards []cityCard      `json:"unlockedCityCards,omitempty"`
}

type mediaUploadResp struct {
	ObjectKey string `json:"objectKey"`
	URL       string `json:"url"`
}

type profileResp struct {
	ID                string          `json:"id"`
	DisplayName       string          `json:"displayName"`
	Bio               string          `json:"bio"`
	Loadout           map[string]any  `json:"loadout"`
	Journeys          []journeyRecord `json:"journeys"`
	UnlockedCityCards []cityCard      `json:"unlockedCityCards"`
}

func main() {
	port := getenv("PORT", "8080")
	dataFile := getenv("DATA_FILE", "./data.json")
	secret := getenv("JWT_SECRET", "change-me-in-production")
	mediaDir := getenv("MEDIA_DIR", "./media")
	mediaURL := getenv("MEDIA_PUBLIC_BASE", "")
	r2, err := newR2StoreFromEnv()
	if err != nil {
		log.Fatal(err)
	}

	st, err := newStore(dataFile)
	if err != nil {
		log.Fatal(err)
	}
	if err := os.MkdirAll(mediaDir, 0o755); err != nil {
		log.Fatal(err)
	}

	s := &server{store: st, jwt: &jwtSigner{secret: []byte(secret)}, mediaDir: mediaDir, mediaURL: mediaURL, r2: r2}
	mux := http.NewServeMux()
	mux.HandleFunc("/v1/health", s.handleHealth)
	mux.HandleFunc("/v1/auth/email/register", s.handleEmailRegister)
	mux.HandleFunc("/v1/auth/email/login", s.handleEmailLogin)
	mux.HandleFunc("/v1/auth/oauth", s.handleOAuthLogin)
	mux.HandleFunc("/v1/friends", s.handleFriends)
	mux.HandleFunc("/v1/friends/", s.handleFriendDelete)
	mux.HandleFunc("/v1/journeys/migrate", s.handleJourneysMigrate)
	mux.HandleFunc("/v1/profile/me", s.handleProfileMe)
	mux.HandleFunc("/v1/profile/", s.handleProfileByID)
	mux.HandleFunc("/v1/media/upload", s.handleMediaUpload)
	mux.Handle("/media/", http.StripPrefix("/media/", http.FileServer(http.Dir(mediaDir))))

	h := withCORS(mux)
	log.Printf("streetstamps backend listening on :%s", port)
	if err := http.ListenAndServe(":"+port, h); err != nil {
		log.Fatal(err)
	}
}

func newStore(path string) (*store, error) {
	s := &store{
		path: path,
		data: db{Users: map[string]*userRecord{}, EmailIndex: map[string]string{}, InviteIndex: map[string]string{}, OAuthIndex: map[string]string{}},
	}
	if err := s.load(); err != nil {
		return nil, err
	}
	return s, nil
}

func (s *store) load() error {
	s.mu.Lock()
	defer s.mu.Unlock()
	b, err := os.ReadFile(s.path)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return err
	}
	if len(b) == 0 {
		return nil
	}
	if err := json.Unmarshal(b, &s.data); err != nil {
		return err
	}
	if s.data.Users == nil {
		s.data.Users = map[string]*userRecord{}
	}
	if s.data.EmailIndex == nil {
		s.data.EmailIndex = map[string]string{}
	}
	if s.data.InviteIndex == nil {
		s.data.InviteIndex = map[string]string{}
	}
	if s.data.OAuthIndex == nil {
		s.data.OAuthIndex = map[string]string{}
	}
	return nil
}

func (s *store) saveLocked() error {
	if err := os.MkdirAll(filepath.Dir(s.path), 0o755); err != nil {
		return err
	}
	b, err := json.MarshalIndent(s.data, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(s.path, b, 0o644)
}

func (s *server) handleHealth(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (s *server) handleEmailRegister(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}
	var req emailAuthReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid json")
		return
	}
	email := strings.ToLower(strings.TrimSpace(req.Email))
	if !strings.Contains(email, "@") || len(req.Password) < 8 {
		writeError(w, http.StatusBadRequest, "invalid email or password")
		return
	}

	s.store.mu.Lock()
	defer s.store.mu.Unlock()
	if _, exists := s.store.data.EmailIndex[email]; exists {
		writeError(w, http.StatusConflict, "email already exists")
		return
	}

	uid := "u_" + randHex(12)
	invite := genInviteCode()
	user := &userRecord{ID: uid, Provider: "email", Email: email, PasswordHash: hashPassword(req.Password), InviteCode: invite, DisplayName: "Explorer", Bio: "Travel Enthusiastic", Loadout: defaultLoadout(), Journeys: []journeyRecord{}, CityCards: []cityCard{}, FriendIDs: []string{}, CreatedAt: time.Now().Unix()}
	s.store.data.Users[uid] = user
	s.store.data.EmailIndex[email] = uid
	s.store.data.InviteIndex[invite] = uid
	if err := s.store.saveLocked(); err != nil {
		writeError(w, http.StatusInternalServerError, "save failed")
		return
	}

	resp, err := s.newAuthResp(user)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "token failed")
		return
	}
	writeJSON(w, http.StatusOK, resp)
}

func (s *server) handleEmailLogin(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}
	var req emailAuthReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid json")
		return
	}
	email := strings.ToLower(strings.TrimSpace(req.Email))

	s.store.mu.RLock()
	uid, ok := s.store.data.EmailIndex[email]
	if !ok {
		s.store.mu.RUnlock()
		writeError(w, http.StatusNotFound, "account not found")
		return
	}
	user := s.store.data.Users[uid]
	s.store.mu.RUnlock()

	if user == nil || user.PasswordHash != hashPassword(req.Password) {
		writeError(w, http.StatusUnauthorized, "wrong email or password")
		return
	}
	resp, err := s.newAuthResp(user)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "token failed")
		return
	}
	writeJSON(w, http.StatusOK, resp)
}

func (s *server) handleOAuthLogin(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}
	var req oauthReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid json")
		return
	}
	provider := strings.ToLower(strings.TrimSpace(req.Provider))
	if provider != "apple" && provider != "google" {
		writeError(w, http.StatusBadRequest, "provider must be apple or google")
		return
	}
	if strings.TrimSpace(req.IDToken) == "" {
		writeError(w, http.StatusBadRequest, "idToken required")
		return
	}
	key := provider + ":" + hashSHA256(req.IDToken)

	s.store.mu.Lock()
	var user *userRecord
	if uid, ok := s.store.data.OAuthIndex[key]; ok {
		user = s.store.data.Users[uid]
	} else {
		uid := "u_" + randHex(12)
		invite := genInviteCode()
		user = &userRecord{ID: uid, Provider: provider, InviteCode: invite, DisplayName: "Explorer", Bio: "Travel Enthusiastic", Loadout: defaultLoadout(), Journeys: []journeyRecord{}, CityCards: []cityCard{}, FriendIDs: []string{}, CreatedAt: time.Now().Unix()}
		s.store.data.Users[uid] = user
		s.store.data.InviteIndex[invite] = uid
		s.store.data.OAuthIndex[key] = uid
	}
	if err := s.store.saveLocked(); err != nil {
		s.store.mu.Unlock()
		writeError(w, http.StatusInternalServerError, "save failed")
		return
	}
	s.store.mu.Unlock()

	resp, err := s.newAuthResp(user)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "token failed")
		return
	}
	writeJSON(w, http.StatusOK, resp)
}

func (s *server) handleFriends(w http.ResponseWriter, r *http.Request) {
	uid, err := s.userFromBearer(r)
	if err != nil {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	switch r.Method {
	case http.MethodGet:
		s.store.mu.RLock()
		me := s.store.data.Users[uid]
		if me == nil {
			s.store.mu.RUnlock()
			writeError(w, http.StatusUnauthorized, "user not found")
			return
		}
		out := make([]friendDTO, 0, len(me.FriendIDs))
		for _, fid := range me.FriendIDs {
			if f := s.store.data.Users[fid]; f != nil {
				out = append(out, toFriendDTOForViewer(f, true))
			}
		}
		s.store.mu.RUnlock()
		writeJSON(w, http.StatusOK, out)
		return

	case http.MethodPost:
		var req addFriendReq
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeError(w, http.StatusBadRequest, "invalid json")
			return
		}
		displayName := strings.TrimSpace(req.DisplayName)
		if displayName == "" {
			writeError(w, http.StatusBadRequest, "displayName required")
			return
		}

		s.store.mu.Lock()
		defer s.store.mu.Unlock()
		me := s.store.data.Users[uid]
		if me == nil {
			writeError(w, http.StatusUnauthorized, "user not found")
			return
		}

		var target *userRecord
		if req.InviteCode != nil && strings.TrimSpace(*req.InviteCode) != "" {
			code := strings.ToUpper(strings.TrimSpace(*req.InviteCode))
			if targetUID, ok := s.store.data.InviteIndex[code]; ok {
				target = s.store.data.Users[targetUID]
			}
		}
		if target == nil {
			target = &userRecord{ID: "f_" + randHex(12), Provider: "manual", InviteCode: genInviteCode(), DisplayName: displayName, Bio: "Travel Enthusiastic", Loadout: defaultLoadout(), Journeys: seedDemoJourneys(), CityCards: seedDemoCityCards(), FriendIDs: []string{}, CreatedAt: time.Now().Unix()}
			s.store.data.Users[target.ID] = target
			s.store.data.InviteIndex[target.InviteCode] = target.ID
		}

		if target.ID != me.ID {
			me.FriendIDs = appendUnique(me.FriendIDs, target.ID)
			target.FriendIDs = appendUnique(target.FriendIDs, me.ID)
		}
		if err := s.store.saveLocked(); err != nil {
			writeError(w, http.StatusInternalServerError, "save failed")
			return
		}
		writeJSON(w, http.StatusOK, toFriendDTOForViewer(target, true))
		return
	default:
		writeError(w, http.StatusMethodNotAllowed, "method not allowed")
	}
}

func (s *server) handleFriendDelete(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodDelete {
		writeError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}
	uid, err := s.userFromBearer(r)
	if err != nil {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	friendID := strings.TrimSpace(strings.TrimPrefix(r.URL.Path, "/v1/friends/"))
	if friendID == "" {
		writeError(w, http.StatusBadRequest, "friend id required")
		return
	}
	
	s.store.mu.Lock()
	defer s.store.mu.Unlock()
	me := s.store.data.Users[uid]
	if me == nil {
		writeError(w, http.StatusUnauthorized, "user not found")
		return
	}
	me.FriendIDs = removeID(me.FriendIDs, friendID)
	if f := s.store.data.Users[friendID]; f != nil {
		f.FriendIDs = removeID(f.FriendIDs, uid)
	}
	if err := s.store.saveLocked(); err != nil {
		writeError(w, http.StatusInternalServerError, "save failed")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{})
}

func (s *server) handleJourneysMigrate(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}
	uid, err := s.userFromBearer(r)
	if err != nil {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	var req migrateReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid json")
		return
	}
	for i := range req.Journeys {
		req.Journeys[i].Visibility = normalizeVisibility(req.Journeys[i].Visibility)
	}

	s.store.mu.Lock()
	defer s.store.mu.Unlock()
	me := s.store.data.Users[uid]
	if me == nil {
		writeError(w, http.StatusUnauthorized, "user not found")
		return
	}
	me.Journeys = req.Journeys
	me.CityCards = req.UnlockedCityCards
	if err := s.store.saveLocked(); err != nil {
		writeError(w, http.StatusInternalServerError, "save failed")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"journeys": len(me.Journeys), "cityCards": len(me.CityCards)})
}

func (s *server) handleProfileMe(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}
	uid, err := s.userFromBearer(r)
	if err != nil {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	
	s.store.mu.RLock()
	me := s.store.data.Users[uid]
	s.store.mu.RUnlock()
	if me == nil {
		writeError(w, http.StatusNotFound, "user not found")
		return
	}
	writeJSON(w, http.StatusOK, profileResp{ID: me.ID, DisplayName: me.DisplayName, Bio: me.Bio, Loadout: me.Loadout, Journeys: me.Journeys, UnlockedCityCards: me.CityCards})
}

func (s *server) handleProfileByID(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}
	viewerID, err := s.userFromBearer(r)
	if err != nil {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	targetID := strings.TrimSpace(strings.TrimPrefix(r.URL.Path, "/v1/profile/"))
	if targetID == "" || targetID == "me" {
		s.handleProfileMe(w, r)
		return
	}

	s.store.mu.RLock()
	viewer := s.store.data.Users[viewerID]
	target := s.store.data.Users[targetID]
	s.store.mu.RUnlock()
	if viewer == nil || target == nil {
		writeError(w, http.StatusNotFound, "user not found")
		return
	}
	isSelf := viewerID == targetID
	isFriend := containsID(viewer.FriendIDs, targetID)
	visible := filterJourneys(target.Journeys, isSelf, isFriend)
	cards := []cityCard{}
	if isSelf || isFriend {
		cards = target.CityCards
	}
	writeJSON(w, http.StatusOK, profileResp{ID: target.ID, DisplayName: target.DisplayName, Bio: target.Bio, Loadout: target.Loadout, Journeys: visible, UnlockedCityCards: cards})
}

func (s *server) handleMediaUpload(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}
	uid, err := s.userFromBearer(r)
	if err != nil {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	if err := r.ParseMultipartForm(50 << 20); err != nil {
		writeError(w, http.StatusBadRequest, "invalid multipart")
		return
	}
	file, fh, err := r.FormFile("file")
	if err != nil {
		writeError(w, http.StatusBadRequest, "file required")
		return
	}
	defer file.Close()
	fileBytes, err := io.ReadAll(file)
	if err != nil {
		writeError(w, http.StatusBadRequest, "read file failed")
		return
	}

	ext := safeExt(fh)
	objectKey := filepath.Join(uid, fmt.Sprintf("%s%s", randHex(16), ext))

	objectKey = filepath.ToSlash(objectKey)
	if s.r2 != nil {
		if uploadErr := s.r2.uploadBytes(r.Context(), objectKey, fileBytes, fh.Header.Get("Content-Type")); uploadErr == nil {
			writeJSON(w, http.StatusOK, mediaUploadResp{ObjectKey: objectKey, URL: s.r2.publicURL(objectKey)})
			return
		} else {
			log.Printf("r2 upload failed, fallback to local disk: %v", uploadErr)
		}
	}

	fullPath := filepath.Join(s.mediaDir, objectKey)
	if err := os.MkdirAll(filepath.Dir(fullPath), 0o755); err != nil {
		writeError(w, http.StatusInternalServerError, "mkdir failed")
		return
	}
	out, err := os.Create(fullPath)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "create file failed")
		return
	}
	defer out.Close()
	if _, err := io.Copy(out, bytes.NewReader(fileBytes)); err != nil {
		writeError(w, http.StatusInternalServerError, "write file failed")
		return
	}

	url := strings.TrimRight(s.mediaURL, "/") + "/media/" + objectKey
	if strings.TrimSpace(s.mediaURL) == "" {
		url = "/media/" + objectKey
	}
	writeJSON(w, http.StatusOK, mediaUploadResp{ObjectKey: objectKey, URL: url})
}

func (s *server) newAuthResp(u *userRecord) (authResp, error) {
	access, err := s.jwt.sign(tokenClaims{UID: u.ID, Prv: u.Provider, Typ: "access", Iat: time.Now().Unix(), Exp: time.Now().Add(2 * time.Hour).Unix()})
	if err != nil {
		return authResp{}, err
	}
	refresh, err := s.jwt.sign(tokenClaims{UID: u.ID, Prv: u.Provider, Typ: "refresh", Iat: time.Now().Unix(), Exp: time.Now().Add(30 * 24 * time.Hour).Unix()})
	if err != nil {
		return authResp{}, err
	}
	var email *string
	if u.Email != "" {
		e := u.Email
		email = &e
	}
	return authResp{UserID: u.ID, Provider: u.Provider, Email: email, AccessToken: access, RefreshToken: refresh}, nil
}

func (s *server) userFromBearer(r *http.Request) (string, error) {
	h := r.Header.Get("Authorization")
	if !strings.HasPrefix(h, "Bearer ") {
		return "", errors.New("missing bearer")
	}
	claims, err := s.jwt.verify(strings.TrimSpace(strings.TrimPrefix(h, "Bearer ")))
	if err != nil {
		return "", err
	}
	if claims.Typ != "access" || claims.Exp <= time.Now().Unix() {
		return "", errors.New("token invalid")
	}
	return claims.UID, nil
}

func (j *jwtSigner) sign(c tokenClaims) (string, error) {
	head := map[string]string{"alg": "HS256", "typ": "JWT"}
	hb, _ := json.Marshal(head)
	cb, _ := json.Marshal(c)
	h64 := base64.RawURLEncoding.EncodeToString(hb)
	c64 := base64.RawURLEncoding.EncodeToString(cb)
	msg := h64 + "." + c64
	mac := hmac.New(sha256.New, j.secret)
	_, _ = mac.Write([]byte(msg))
	sig := base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
	return msg + "." + sig, nil
}

func (j *jwtSigner) verify(tok string) (tokenClaims, error) {
	parts := strings.Split(tok, ".")
	if len(parts) != 3 {
		return tokenClaims{}, errors.New("invalid token")
	}
	msg := parts[0] + "." + parts[1]
	mac := hmac.New(sha256.New, j.secret)
	_, _ = mac.Write([]byte(msg))
	expect := base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
	if !hmac.Equal([]byte(expect), []byte(parts[2])) {
		return tokenClaims{}, errors.New("bad signature")
	}
	payload, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return tokenClaims{}, err
	}
	var c tokenClaims
	if err := json.Unmarshal(payload, &c); err != nil {
		return tokenClaims{}, err
	}
	return c, nil
}

func withCORS(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func toFriendDTOForViewer(u *userRecord, isFriend bool) friendDTO {
	return friendDTO{
		ID:                u.ID,
		InviteCode:        u.InviteCode,
		DisplayName:       u.DisplayName,
		Bio:               u.Bio,
		Loadout:           u.Loadout,
		Journeys:          filterJourneys(u.Journeys, false, isFriend),
		UnlockedCityCards: u.CityCards,
	}
}

func filterJourneys(in []journeyRecord, isSelf bool, isFriend bool) []journeyRecord {
	if isSelf {
		return in
	}
	out := make([]journeyRecord, 0, len(in))
	for _, j := range in {
		v := normalizeVisibility(j.Visibility)
		switch v {
		case visibilityPublic:
			out = append(out, j)
		case visibilityFriendsOnly:
			if isFriend {
				out = append(out, j)
			}
		}
	}
	return out
}

func normalizeVisibility(v string) string {
	s := strings.TrimSpace(v)
	switch s {
	case visibilityPublic, visibilityFriendsOnly, visibilityPrivate:
		return s
	default:
		return visibilityPrivate
	}
}

func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}

func writeError(w http.ResponseWriter, code int, msg string) {
	writeJSON(w, code, serverError{Message: msg})
}

func appendUnique(ids []string, id string) []string {
	for _, v := range ids {
		if v == id {
			return ids
		}
	}
	return append(ids, id)
}

func removeID(ids []string, id string) []string {
	out := ids[:0]
	for _, v := range ids {
		if v != id {
			out = append(out, v)
		}
	}
	return out
}

func containsID(ids []string, id string) bool {
	for _, v := range ids {
		if v == id {
			return true
		}
	}
	return false
}

func defaultLoadout() map[string]any {
	return map[string]any{
		"bodyId":       "body",
		"headId":       "head",
		"skinId":       "skin_default",
		"hairId":       "hair_boy_default",
		"outfitId":     "outfit_boy_suit",
		"accessoryIds": []string{"acc_headphone"},
		"expressionId": "expr_default",
	}
}

func seedDemoJourneys() []journeyRecord {
	now := time.Now().UTC()
	t1 := now.Add(-48 * time.Hour)
	t2 := now.Add(-47*time.Hour + 30*time.Minute)
	m1 := now.Add(-47 * time.Hour)
	return []journeyRecord{{ID: "j_" + randHex(8), Title: "City Walk", ActivityTag: "步行", Overall: "在城市里慢慢走，拍到了很多街角光影。", Distance: 6200, StartTime: &t1, EndTime: &t2, Visibility: visibilityPublic, Memories: []memoryRecord{{ID: "m_" + randHex(8), Title: "街边咖啡", Notes: "转角那家店的拿铁很稳。", Timestamp: m1}}}}
}

func seedDemoCityCards() []cityCard {
	return []cityCard{{ID: "Shanghai|CN", Name: "Shanghai", CountryISO2: "CN"}, {ID: "Hangzhou|CN", Name: "Hangzhou", CountryISO2: "CN"}}
}

func hashPassword(pw string) string {
	return hashSHA256("StreetStamps::" + pw)
}

func hashSHA256(raw string) string {
	h := sha256.Sum256([]byte(raw))
	return hex.EncodeToString(h[:])
}

func genInviteCode() string {
	return strings.ToUpper(randHex(4))
}

func randHex(n int) string {
	if n <= 0 {
		return ""
	}
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		return fmt.Sprintf("%d", time.Now().UnixNano())
	}
	return hex.EncodeToString(b)
}

func safeExt(fh *multipart.FileHeader) string {
	ext := strings.ToLower(filepath.Ext(fh.Filename))
	switch ext {
	case ".jpg", ".jpeg", ".png", ".webp", ".heic", ".gif", ".mp4", ".mov":
		return ext
	default:
		return ".bin"
	}
}

func newR2StoreFromEnv() (*r2Store, error) {
	accountID := strings.TrimSpace(os.Getenv("R2_ACCOUNT_ID"))
	accessKeyID := strings.TrimSpace(os.Getenv("R2_ACCESS_KEY_ID"))
	secretKey := strings.TrimSpace(os.Getenv("R2_SECRET_ACCESS_KEY"))
	bucket := strings.TrimSpace(os.Getenv("R2_BUCKET"))
	if accountID == "" || accessKeyID == "" || secretKey == "" || bucket == "" {
		return nil, nil
	}

	endpoint := strings.TrimSpace(os.Getenv("R2_ENDPOINT"))
	if endpoint == "" {
		endpoint = "https://" + accountID + ".r2.cloudflarestorage.com"
	}
	publicBase := strings.TrimRight(strings.TrimSpace(os.Getenv("R2_PUBLIC_BASE")), "/")
	region := getenv("R2_REGION", "auto")
	return &r2Store{
		accessKeyID: accessKeyID,
		secretKey:   secretKey,
		bucket:      bucket,
		publicBase:  publicBase,
		endpoint:    strings.TrimRight(endpoint, "/"),
		region:      region,
	}, nil
}

func (r *r2Store) uploadBytes(ctx context.Context, objectKey string, body []byte, contentType string) error {
	key := strings.TrimLeft(objectKey, "/")
	uri := "/" + r.bucket + "/" + key
	now := time.Now().UTC()
	amzDate := now.Format("20060102T150405Z")
	dateStamp := now.Format("20060102")

	payloadHash := hashBytesSHA256(body)
	host := strings.TrimPrefix(strings.TrimPrefix(r.endpoint, "https://"), "http://")
	canonicalHeaders := "host:" + host + "\n" +
		"x-amz-content-sha256:" + payloadHash + "\n" +
		"x-amz-date:" + amzDate + "\n"
	signedHeaders := "host;x-amz-content-sha256;x-amz-date"
	canonicalRequest := "PUT\n" + uri + "\n\n" + canonicalHeaders + "\n" + signedHeaders + "\n" + payloadHash
	credentialScope := dateStamp + "/" + r.region + "/s3/aws4_request"
	stringToSign := "AWS4-HMAC-SHA256\n" + amzDate + "\n" + credentialScope + "\n" + hashStringSHA256(canonicalRequest)

	signingKey := r.awsSigningKey(dateStamp)
	signature := hex.EncodeToString(hmacSHA256(signingKey, stringToSign))
	authHeader := "AWS4-HMAC-SHA256 Credential=" + r.accessKeyID + "/" + credentialScope + ", SignedHeaders=" + signedHeaders + ", Signature=" + signature

	req, err := http.NewRequestWithContext(ctx, http.MethodPut, r.endpoint+uri, bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("x-amz-date", amzDate)
	req.Header.Set("x-amz-content-sha256", payloadHash)
	req.Header.Set("Authorization", authHeader)
	if contentType != "" {
		req.Header.Set("Content-Type", contentType)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 200 && resp.StatusCode < 300 {
		return nil
	}
	msg, _ := io.ReadAll(io.LimitReader(resp.Body, 4<<10))
	return fmt.Errorf("r2 put failed: status=%d body=%s", resp.StatusCode, strings.TrimSpace(string(msg)))
}

func (r *r2Store) publicURL(objectKey string) string {
	key := strings.TrimLeft(objectKey, "/")
	if r.publicBase != "" {
		return r.publicBase + "/" + key
	}
	return r.endpoint + "/" + r.bucket + "/" + key
}

func (r *r2Store) awsSigningKey(dateStamp string) []byte {
	kDate := hmacSHA256([]byte("AWS4"+r.secretKey), dateStamp)
	kRegion := hmacSHA256(kDate, r.region)
	kService := hmacSHA256(kRegion, "s3")
	return hmacSHA256(kService, "aws4_request")
}

func hashStringSHA256(s string) string {
	sum := sha256.Sum256([]byte(s))
	return hex.EncodeToString(sum[:])
}

func hashBytesSHA256(b []byte) string {
	sum := sha256.Sum256(b)
	return hex.EncodeToString(sum[:])
}

func hmacSHA256(key []byte, s string) []byte {
	m := hmac.New(sha256.New, key)
	_, _ = m.Write([]byte(s))
	return m.Sum(nil)
}

func getenv(k, def string) string {
	v := strings.TrimSpace(os.Getenv(k))
	if v == "" {
		return def
	}
	return v
}
