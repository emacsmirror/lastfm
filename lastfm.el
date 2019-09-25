;; -*- lexical-binding: t -*-

(require 'request)
(require 'cl-lib)
(require 'elquery)
(require 's)

;;;; Configuration and setup
(defconst lastfm--url "http://ws.audioscrobbler.com/2.0/"
  "The URL for the last.fm API version 2 used to make all the
  method calls.")

(defconst lastfm--config-file
  (let ((f (concat (xdg-config-home) "/.lastfmrc")))
    (or (file-exists-p f)
        (with-temp-file f
          (insert "(CONFIG
  :API-KEY \"\"
  :SHARED-SECRET \"\"
  :USERNAME \"\")")))
    f)
  "User config file holding the last.fm api-key, shared-secret,
username and the session key. If the file does not exist when the
package is loaded, build it with empty values.")

;; The values of these configs are taken from the user config file.
(defvar lastfm--api-key)
(defvar lastfm--shared-secret)
(defvar lastfm--username)
(defvar lastfm--sk)

(defun lastfm--read-config-file ()
  "Return the config file contents as a Lisp object"
  (with-temp-buffer
    (insert-file-contents lastfm--config-file)
    (read (buffer-string))))

(defun lastfm--set-config-parameters ()
  "Read the config file and set the config parameters used
throught the package."
  (let ((config (cl-rest (lastfm--read-config-file))))
    (cl-mapcar (lambda (key value)
                 (setf (pcase key
                         (:API-KEY       lastfm--api-key)
                         (:SHARED-SECRET lastfm--shared-secret)
                         (:USERNAME      lastfm--username)
                         (:SK            lastfm--sk))
                       value))
               (cl-remove-if #'stringp config)
               (cl-remove-if #'symbolp config))))

(lastfm--set-config-parameters)         ;set params on start-up.

(defun lastfm-generate-session-key ()
  "Get an authorization token from last.fm and then ask the user
to grant persmission to his last.fm account. If granted, then ask
for the session key (sk) and append the sk value to the config's
file list of values."
  (let ((token (cl-first (lastfm-auth-gettoken))))
    ;; Ask the user to allow access.
    (browse-url (concat "http://www.last.fm/api/auth/?api_key="
                        lastfm--api-key
                        "&token=" token))
    (when (yes-or-no-p "Did you grant the application persmission 
to access your Last.fm account? ")
      ;; If permission granted, get the sk and update the config file.
      (let* ((sk (cl-first (lastfm-auth-getsession token)))
             (config (lastfm--read-config-file))
             (config-with-sk (append config (list :SK sk))))
        (with-temp-file lastfm--config-file
          (insert (prin1-to-string config-with-sk))))
      (lastfm--set-config-parameters)   ;set params on config file update.
      )))


;;;; Methods list, and functions for it's manipulation
(defconst lastfm--methods-pretty
  '((album
     (addtags    :yes (artist album tags) ()           "lfm")
     (getinfo    :no  (artist album)      ()           "track > name")
     (gettags    :yes (artist album)      ()           "tag name")
     (gettoptags :no  (artist album)      ()           "tag name")
     (removetag  :yes (artist album tag)  ()           "lfm")
     (search     :no  (album)             ((limit 10)) "album artist"))
    
    (artist
     (addtags       :yes (artist tags) () "lfm")
     (getcorrection :no  (artist) ()       "artist name")
     (getinfo       :no  (artist) ()       "bio summary")
     (getsimilar    :no  (artist) ((limit lastfm--similar-limit)
                                   (user lastfm--username))
                    "artist name")
     (gettags       :yes (artist)     ()                    "tag name")
     (gettopalbums  :no  (artist)     ((limit 50))          "album > name")
     (gettoptags    :no  (artist)     ()                    "tag name")
     (gettoptracks  :no  (artist)     ((limit 50) (page 1))
                    ("artist > name" "track > name" "track > playcount"))
     (removetag     :yes (artist tag) ()                    "lfm")
     (search        :no  (artist)     ((limit 30))          "artist name"))
    
    (auth
     (gettoken   :sk ()      () "token")
     (getsession :sk (token) () "session key"))

    (chart
     (gettopartists :no () ((limit 50)) "name")
     (gettoptags    :no () ((limit 50)) "name")
     (gettoptracks  :no () ((limit 50)) "artist > name, track > name, track > listeners"))

    (geo
     (gettopartists :no (country) ((limit 50) (page 1)) "artist name")
     (gettoptracks  :no (country) ((limit 50) (page 1))
                    ("artist > name" "track > name")))

    (library
     (getartists :no () ((user lastfm--username) (limit 50) (page 1)) "artist name"))

    (tag
     (getinfo       :no (tag) ()                    "summary")
     (getsimilar    :no (tag) ()                    "tag name") ;Doesn't return anything
     (gettopalbums  :no (tag) ((limit 50) (page 1)) "album > name, artist > name")
     (gettopartists :no (tag) ((limit 50) (page 1)) "artist name")
     (gettoptags    :no () ()                       "name")
     (gettoptracks  :no (tag) ((limit 50) (page 1)) "track > name, artist > name"))
    
    (track
     (addtags          :yes (artist track tags) () "lfm")
     (getcorrection    :no (artist track) () "track > name, artist > name")
     (getinfo          :no (artist track) ()                          "album title")
     (getsimilar       :no (artist track) ((limit 10))
                       "track > name, artist > name")
     ;; Method doesn't return anything from lastfm
     (gettags          :yes (artist track) ()                         "name") 
     (gettoptags       :no (artist track) ()                          "name")
     (love             :yes (artist track) ()                         "lfm")
     (removetag        :yes (artist track tag) ()                     "lfm")
     (scrobble         :yes (artist track timestamp) ()               "lfm")
     (search           :no (track) ((artist nil) (limit 30) (page 1)) "name, artist")
     (unlove           :yes (artist track) ()                         "lfm")
     (updatenowplaying :yes (artist track)
                       ((album nil) (tracknumber nil) (context nil) (duration nil)
                        (albumartist nil)) "lfm"))
    
    (user
     (getfriends :no (user) ((recenttracks nil) (limit 50) (page 1)) "name")
     (getinfo :no () ((user lastfm--username)) "playcount, country")
     (getlovedtracks :no  () ((user lastfm--username) (limit 50) (page 1))
                     "artist > name, track > name" )
     (getpersonaltags :no (tag taggingtype)
                      ((user lastfm--username) (limit 50) (page 1)) "name")
     (getrecenttracks :no () ((user lastfm--username) (limit nil) (page nil)
                              (from nil) (to nil) (extended 0))
                      "artist, track > name")
     (gettopalbums :no () ((user lastfm--username) (period nil)
                           (limit nil) (page nil))
                   "artist > name, album > name")
     (gettopartists :no () ((user lastfm--username) (period nil)
                            (limit nil) (page nil))
                    "artist name")
     (gettoptags :no () ((user lastfm--username) (limit nil)) "tag name")
     (gettoptracks :no () ((user lastfm--username) (period nil)
                            (limit nil) (page nil))
                   "artist > name, track > name")
     (getweeklyalbumchart :no () ((user lastfm--username) (from nil) (to nil))
                          "album > artist, album > name")
     (getweeklyartistchart :no () ((user lastfm--username) (from nil) (to nil))
                           "album > name, artist > playcount")
     (getweeklytrackchart :no () ((user lastfm--username) (from nil) (to nil))
                          "track > artist, track > name")))
  "List of all the supported lastfm methods. A one liner
like (artist-getinfo ...) or (track-love ...) is more easier to
parse, but this is easier for the eyes. The latter, the
one-liner, is generated from this list and is the one actually
used for all the processing and generation of the user API. ")

(defconst lastfm--methods
  (let ((res nil))
    (mapcar
     (lambda (group)
       (mapcar
        (lambda (method)
          (push (cons (make-symbol
                       (concat (symbol-name (cl-first group)) "-"
                               (symbol-name (cl-first method))))
                      (cl-rest method))
                res))
        (cl-rest group)))
     lastfm--methods-pretty)
    (reverse res))
  "Generated list of one-liner lastfm methods from the pretty
list of methods. Each entry in this list is a complete lastm
method specification. It is used to generate the API for this
library.")

(defun lastfm--method-name (method)
  (cl-first method))

(defun lastfm--method-str (method)
  "The method name, as a string that can be used in a lastfm
request."
  (s-replace "-" "." (symbol-name (lastfm--method-name method))))

(defun lastfm--auth-p (method)
  "Does this method require authentication?"
  (eql (cl-second method) :yes))

(defun lastfm--sk-p (method)
  "Is this a method used for requesting the session key?"
  (eql (cl-second method) :sk))

(defun lastfm--method-params (method)
  "Minimum required parameters for succesfully calling this method."
  (cl-third method))

(defun lastfm--method-keyword-params (method)
  (cl-fourth method))

(defun lastfm--all-method-params (method)
  "A list of all the method parameters, required plus keyword."
  (append (lastfm--method-params method)
          (mapcar #'car (lastfm--method-keyword-params method))))

(defun lastfm--query-strings (method)
  "XML query string for extracting the relevant data from the
lastfm response."
  (cl-fifth method))

(defun lastfm--group-params-for-signing (params)
  "The signing procedure for authentication needs all the
parameters and values lumped together in one big string without
equal or ampersand symbols between them."
  (let ((res ""))
    (mapcar (lambda (s)
              (setf res (concat res (car s) (cdr s))))
            params)
    (concat res lastfm--shared-secret)))

(defun lastfm--build-params (method values)
  "Build the parameter/value list to be used by request :params."
  (let ((result
         `(;; The api key and method is needed for all calls.
           ("api_key" . ,lastfm--api-key)
           ("method" . ,(lastfm--method-str method))
           ;; Pair the user supplied values with the method parameters.  If no
           ;; value supplied for a given param, do not include it in the request.
           ,@(cl-remove-if #'null
              (cl-mapcar (lambda (param value)
                           (when value
                             (cons (symbol-name param) value)))
                         (lastfm--all-method-params method)
                         values)))))
    ;; Session Key(SK) parameter is needed for all auth services, but not for
    ;; the services used to obtain the SK.
    (when (lastfm--auth-p method)
      (push `("sk" . ,lastfm--sk) result))
    ;; If signing is needed, it should be added as the last parameter.
    (when (or (lastfm--auth-p method)
              (lastfm--sk-p method))
      ;; Params need to be in alphabetical order before signing.
      (setq result (cl-sort result #'string-lessp
                            :key #'cl-first))
      (add-to-list 'result
                   `("api_sig" . ,(md5 (lastfm--group-params-for-signing result)))
                   t))
    result))

(cl-defun lastfm--request (method &rest values)
  (let ((resp ""))
    (request lastfm--url
             :params   (lastfm--build-params method values)
             :parser   'buffer-string
             :type     "POST"
             :sync     t
             :complete (cl-function
                        (lambda (&key data &allow-other-keys)
                          (setq resp data))))
    resp))

(defun lastfm--key-from-query-str (query-string)
  "Use the query string to build a key usable in alists."
  (declare (string method-name))
  (make-symbol
   (s-replace " " ""
              (s-replace ">" "-" query-string))))

(defun lastfm--parse-response (response method)
  (let* ((raw-response (elquery-read-string response))
         ;; Only one error expected, if any.
         (error-str (elquery-text
                     (cl-first (elquery-$ "error" raw-response)))))
    (if error-str
        (error error-str)
      (let ((query-strings (lastfm--query-strings method)))
        (cl-labels
            ((helper (queries)
                     (if (null queries)
                         '()
                       ;; Use the same raw response to extract a different text
                       ;; object each time, according to the current query
                       ;; string. Build an alist from the query string and the
                       ;; extracted text object.
                       (cons (--map (cons (lastfm--key-from-query-str (car queries))
                                          (elquery-text it))
                                    (elquery-$ (car queries) raw-response))
                             (helper (cdr queries))))))
          (let ((result (helper query-strings)))            
            (reverse
             ;; The cons from the helper method above groups all the text
             ;; objects from the first query string together, followed by all
             ;; the text objects from the next query string grouped together and
             ;; so on until all the query strings are exhausted. If the query
             ;; string would look like '("artist" "song") then we would have
             ;; '((artist1 artist2) (song1 song2)) as a result from the helper
             ;; method, but we want '((artist1 songs1) (artist2 song2)) instead.
             (if (= (length query-strings) 2)
                 ;; Workaround for -zip returning a cons cell instead of a list
                 ;; when two lists are provided to it.
                 (-zip-with #'list (cl-first result) (cl-second result))
               (apply #'-zip (helper query-strings))))))))))

(defun lastfm--build-function (method)
  (let* ((name-str (symbol-name (lastfm--method-name method)))
         (fn-name (intern (concat "lastfm-" name-str)))
         (params (lastfm--method-params method))
         (key-params (lastfm--method-keyword-params method)))
    `(cl-defun ,fn-name ,(if key-params
                             `(,@params &key ,@key-params)
                           `,@params)
       (lastfm--parse-response
        (lastfm--request ',method
                         ,@(if key-params
                               `(,@params ,@(mapcar #'car key-params))
                             `,params))
        ',method))))

(defmacro lastfm--build-api ()
  `(progn
     ,@(mapcar (lambda (method)
                 (lastfm--build-function method))
               lastfm--methods)))

(lastfm--build-api)

(provide 'lastfm)
