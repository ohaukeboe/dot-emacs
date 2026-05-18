;;; lsp-mcp-test.el --- Tests for lsp-mcp -*- lexical-binding: t; -*-

;;; Commentary:
;; ERT tests for lsp-mcp.el.
;;
;; Most tests exercise pure helpers and require no live LSP server.
;; Tool-registration tests use `mcp-server-lib-ert' to spin up an
;; in-process MCP server and verify the six tools are exposed.
;;
;; Run from the package directory with:
;;   emacs -batch -L . -l lsp-mcp-test.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'json)
(require 'lsp-mcp)
(require 'mcp-server-lib)
(require 'mcp-server-lib-ert)

(setq mcp-server-lib-ert-server-id "lsp-mcp")


;;; Pure helpers — no LSP required

(ert-deftest lsp-mcp-test-parse-int-number ()
  (should (= 42 (lsp-mcp--parse-int 42))))

(ert-deftest lsp-mcp-test-parse-int-string ()
  (should (= 42 (lsp-mcp--parse-int "42"))))

(ert-deftest lsp-mcp-test-parse-int-zero-string ()
  (should (= 0 (lsp-mcp--parse-int "0"))))

(ert-deftest lsp-mcp-test-symbol-kind-name-known ()
  (should (string= "Function" (lsp-mcp--symbol-kind-name 12)))
  (should (string= "File" (lsp-mcp--symbol-kind-name 1)))
  (should (string= "TypeParameter" (lsp-mcp--symbol-kind-name 26))))

(ert-deftest lsp-mcp-test-symbol-kind-name-unknown ()
  (should (string= "99" (lsp-mcp--symbol-kind-name 99))))

(ert-deftest lsp-mcp-test-position-params-shape ()
  (let* ((tmp (make-temp-file "lsp-mcp-test" nil ".txt"))
         (params (lsp-mcp--position-params tmp 10 4))
         (pos (plist-get params :position)))
    (unwind-protect
        (progn
          (should (string-prefix-p "file://" (plist-get (plist-get params :textDocument) :uri)))
          ;; line is 1-indexed input → 0-indexed in params
          (should (= 9 (plist-get pos :line)))
          (should (= 4 (plist-get pos :character))))
      (delete-file tmp))))


;;; Location / LocationLink normalization

(ert-deftest lsp-mcp-test-location-p-true ()
  (should (lsp-mcp--location-p
           (list :uri "file:///x.el"
                 :range (list :start (list :line 0 :character 0))))))

(ert-deftest lsp-mcp-test-location-p-false-on-link ()
  (should-not (lsp-mcp--location-p
               (list :targetUri "file:///x.el"
                     :targetRange (list :start (list :line 0 :character 0))))))

(ert-deftest lsp-mcp-test-location-to-alist ()
  (let* ((loc (list :uri "file:///tmp/x.el"
                    :range (list :start (list :line 4 :character 7)
                                 :end   (list :line 4 :character 12))))
         (out (lsp-mcp--location-to-alist loc)))
    (should (string= "/tmp/x.el" (alist-get 'file out)))
    ;; line is converted from 0-indexed (LSP) to 1-indexed (output)
    (should (= 5 (alist-get 'line out)))
    (should (= 7 (alist-get 'column out)))))

(ert-deftest lsp-mcp-test-location-link-to-alist ()
  (let* ((link (list :targetUri "file:///tmp/y.el"
                    :targetRange (list :start (list :line 0 :character 3)
                                       :end   (list :line 0 :character 8))))
         (out (lsp-mcp--location-link-to-alist link)))
    (should (string= "/tmp/y.el" (alist-get 'file out)))
    (should (= 1 (alist-get 'line out)))
    (should (= 3 (alist-get 'column out)))))

(ert-deftest lsp-mcp-test-normalize-locations-nil ()
  (should (null (lsp-mcp--normalize-locations nil))))

(ert-deftest lsp-mcp-test-normalize-locations-empty-vector ()
  (should (null (lsp-mcp--normalize-locations []))))

(ert-deftest lsp-mcp-test-normalize-locations-single-location ()
  (let* ((loc (list :uri "file:///a.el"
                    :range (list :start (list :line 0 :character 0))))
         (out (lsp-mcp--normalize-locations loc)))
    (should (= 1 (length out)))
    (should (string= "/a.el" (alist-get 'file (car out))))))

(ert-deftest lsp-mcp-test-normalize-locations-location-vector ()
  (let* ((locs (vector
                (list :uri "file:///a.el"
                      :range (list :start (list :line 0 :character 0)))
                (list :uri "file:///b.el"
                      :range (list :start (list :line 1 :character 2)))))
         (out (lsp-mcp--normalize-locations locs)))
    (should (= 2 (length out)))
    (should (string= "/a.el" (alist-get 'file (nth 0 out))))
    (should (string= "/b.el" (alist-get 'file (nth 1 out))))
    (should (= 2 (alist-get 'line (nth 1 out))))))

(ert-deftest lsp-mcp-test-normalize-locations-location-link-vector ()
  (let* ((links (vector
                 (list :targetUri "file:///a.el"
                       :targetRange (list :start (list :line 3 :character 1)))))
         (out (lsp-mcp--normalize-locations links)))
    (should (= 1 (length out)))
    (should (string= "/a.el" (alist-get 'file (car out))))
    (should (= 4 (alist-get 'line (car out))))))


;;; DocumentSymbol flattening

(ert-deftest lsp-mcp-test-document-symbols-flatten-flat ()
  (let* ((syms (vector
                (list :name "foo" :kind 12
                      :selectionRange (list :start (list :line 0 :character 0)))
                (list :name "bar" :kind 13
                      :selectionRange (list :start (list :line 5 :character 2)))))
         (out (lsp-mcp--document-symbols-flatten syms)))
    (should (= 2 (length out)))
    (should (string= "foo" (alist-get 'name (nth 0 out))))
    (should (string= "Function" (alist-get 'kind (nth 0 out))))
    (should (= 1 (alist-get 'line (nth 0 out))))
    (should (string= "bar" (alist-get 'name (nth 1 out))))
    (should (= 6 (alist-get 'line (nth 1 out))))))

(ert-deftest lsp-mcp-test-document-symbols-flatten-nested ()
  (let* ((syms (vector
                (list :name "Klass" :kind 5
                      :selectionRange (list :start (list :line 0 :character 0))
                      :children (vector
                                 (list :name "method" :kind 6
                                       :selectionRange
                                       (list :start (list :line 2 :character 4)))))))
         (out (lsp-mcp--document-symbols-flatten syms)))
    (should (= 2 (length out)))
    (should (string= "Klass" (alist-get 'name (nth 0 out))))
    ;; Child name is prefixed by parent breadcrumb
    (should (string= "Klass.method" (alist-get 'name (nth 1 out))))
    (should (string= "Method" (alist-get 'kind (nth 1 out))))
    (should (= 3 (alist-get 'line (nth 1 out))))))

(ert-deftest lsp-mcp-test-document-symbols-flatten-detail ()
  (let* ((syms (vector
                (list :name "f" :kind 12
                      :detail "(arg) -> int"
                      :selectionRange (list :start (list :line 0 :character 0)))
                (list :name "g" :kind 12
                      :detail ""
                      :selectionRange (list :start (list :line 1 :character 0)))))
         (out (lsp-mcp--document-symbols-flatten syms)))
    (should (string= "(arg) -> int" (alist-get 'detail (nth 0 out))))
    ;; Empty detail is dropped
    (should-not (assq 'detail (nth 1 out)))))


;;; Tool registration via mcp-server-lib

(defconst lsp-mcp-test--expected-tool-ids
  '("lsp-find-definitions"
    "lsp-find-references"
    "lsp-hover"
    "lsp-get-diagnostics"
    "lsp-workspace-symbols"
    "lsp-document-symbols"
    "lsp-find-implementations"
    "lsp-find-type-definition"
    "lsp-call-hierarchy"
    "lsp-signature-help"
    "lsp-inlay-hints"
    "lsp-document-highlight"
    "lsp-format-buffer"
    "lsp-format-region"))

(defun lsp-mcp-test--drain-registrations ()
  "Fully remove any lingering lsp-mcp registrations.
The running Emacs may have called `lsp-mcp-enable' at startup; ref-counted
registration means a single `lsp-mcp-disable' would not remove the tool."
  (dolist (id lsp-mcp-test--expected-tool-ids)
    (cl-loop repeat 20
             while (mcp-server-lib-unregister-tool id "lsp-mcp"))))

(ert-deftest lsp-mcp-test-enable-registers-all-tools ()
  (unwind-protect
      (progn
        (lsp-mcp-test--drain-registrations)
        (lsp-mcp-enable)
        (mcp-server-lib-ert-with-server :tools t :resources nil
          (let* ((req (mcp-server-lib-create-tools-list-request))
                 (result (mcp-server-lib-ert-get-success-result "tools/list" req))
                 (tools (alist-get 'tools result))
                 (names (mapcar (lambda (it) (alist-get 'name it))
                                (append tools nil))))
            (dolist (id lsp-mcp-test--expected-tool-ids)
              (should (member id names))))))
    (lsp-mcp-test--drain-registrations)))

(ert-deftest lsp-mcp-test-disable-unregisters-all-tools ()
  "After balanced enable+disable, each tool id must be fully removed."
  (unwind-protect
      (progn
        (lsp-mcp-test--drain-registrations)
        (lsp-mcp-enable)
        (lsp-mcp-disable)
        ;; Each id should now be absent — unregister returns nil.
        (dolist (id lsp-mcp-test--expected-tool-ids)
          (should-not (mcp-server-lib-unregister-tool id "lsp-mcp"))))
    (lsp-mcp-test--drain-registrations)))

(ert-deftest lsp-mcp-test-disable-returns-t-for-each-tool ()
  "Every id registered by `lsp-mcp-enable' must be unregisterable."
  (unwind-protect
      (progn
        (lsp-mcp-test--drain-registrations)
        (lsp-mcp-enable)
        (dolist (id lsp-mcp-test--expected-tool-ids)
          (should (mcp-server-lib-unregister-tool id "lsp-mcp"))))
    (lsp-mcp-test--drain-registrations)))


;;; Error paths — `lsp-mcp--ensure-lsp-buffer'

(ert-deftest lsp-mcp-test-ensure-lsp-buffer-missing-file ()
  (let ((missing "/nonexistent/path/should/not/exist.xyz"))
    (should-error
     ;; mcp-server-lib-tool-throw signals `mcp-server-lib-tool-error'
     (lsp-mcp--ensure-lsp-buffer missing)
     :type 'mcp-server-lib-tool-error)))

;;; call-hierarchy item conversion

(ert-deftest lsp-mcp-test-call-hierarchy-item-to-alist ()
  (let* ((item (list :name "do-thing"
                     :kind 12
                     :uri "file:///src/foo.el"
                     :range (list :start (list :line 9 :character 2)
                                  :end   (list :line 9 :character 10))))
         (out (lsp-mcp--call-hierarchy-item-to-alist item)))
    (should (string= "do-thing" (alist-get 'name out)))
    (should (string= "Function" (alist-get 'kind out)))
    (should (string= "/src/foo.el" (alist-get 'file out)))
    ;; LSP 0-indexed line 9 → 1-indexed 10
    (should (= 10 (alist-get 'line out)))
    (should (= 2  (alist-get 'column out)))))


;;; signature-help formatting (exercised via lsp-mcp--signature-help internals)
;;
;; We test the JSON shape by calling `lsp-mcp--signature-help' with a mocked
;; `lsp-request'.  Use `cl-letf' to stub the request.

(defmacro lsp-mcp-test--with-lsp-request (response &rest body)
  "Execute BODY with `lsp-request' stubbed to return RESPONSE."
  (declare (indent 1))
  `(cl-letf (((symbol-function 'lsp-request) (lambda (_method _params) ,response))
             ((symbol-function 'lsp-mcp--ensure-lsp-buffer)
              (lambda (_file) (current-buffer))))
     ,@body))

(ert-deftest lsp-mcp-test-signature-help-single-sig ()
  (lsp-mcp-test--with-lsp-request
      (list :signatures
            (vector
             (list :label "foo(x: int, y: str) -> bool"
                   :documentation "Does the foo thing."
                   :parameters (vector
                                (list :label "x: int"
                                      :documentation "The x value.")
                                (list :label "y: str"))))
            :activeSignature 0
            :activeParameter 0)
    (let* ((json (lsp-mcp--signature-help "fake.el" 1 0))
           (parsed (json-read-from-string json))
           (sig (aref parsed 0)))
      (should (= 1 (length parsed)))
      (should (string= "foo(x: int, y: str) -> bool" (alist-get 'label sig)))
      (should (string= "Does the foo thing." (alist-get 'documentation sig)))
      (should (eq t (alist-get 'active sig)))
      (should (= 0 (alist-get 'activeParameter sig)))
      (let* ((params (alist-get 'parameters sig))
             (p0 (aref params 0))
             (p1 (aref params 1)))
        (should (string= "x: int" (alist-get 'label p0)))
        (should (string= "The x value." (alist-get 'documentation p0)))
        (should (string= "y: str" (alist-get 'label p1)))
        (should-not (assq 'documentation p1))))))

(ert-deftest lsp-mcp-test-signature-help-nil-response ()
  (lsp-mcp-test--with-lsp-request nil
    (should (string= "[]" (lsp-mcp--signature-help "fake.el" 1 0)))))

(ert-deftest lsp-mcp-test-signature-help-markupcontent-doc ()
  "Documentation as MarkupContent {kind, value} should be extracted as string."
  (lsp-mcp-test--with-lsp-request
      (list :signatures
            (vector
             (list :label "bar()"
                   :documentation (list :kind "markdown" :value "**Bar** docs.")))
            :activeSignature 0)
    (let* ((json (lsp-mcp--signature-help "fake.el" 1 0))
           (parsed (json-read-from-string json))
           (sig (aref parsed 0)))
      (should (string= "**Bar** docs." (alist-get 'documentation sig))))))

(ert-deftest lsp-mcp-test-signature-help-vector-param-label ()
  "Parameter label as [start end] offset vector is resolved to substring."
  (lsp-mcp-test--with-lsp-request
      (list :signatures
            (vector
             (list :label "fn(abc, def)"
                   :parameters (vector
                                (list :label (vector 3 6))   ; "abc"
                                (list :label (vector 8 11))))) ; "def"
            :activeSignature 0)
    (let* ((json (lsp-mcp--signature-help "fake.el" 1 0))
           (parsed (json-read-from-string json))
           (params (alist-get 'parameters (aref parsed 0))))
      (should (string= "abc" (alist-get 'label (aref params 0))))
      (should (string= "def" (alist-get 'label (aref params 1)))))))


;;; inlay hints formatting

(ert-deftest lsp-mcp-test-inlay-hints-basic ()
  (lsp-mcp-test--with-lsp-request
      (vector
       (list :position (list :line 4 :character 8)
             :kind 1
             :label ": i32")
       (list :position (list :line 7 :character 3)
             :kind 2
             :label "value:"))
    (let* ((json (lsp-mcp--inlay-hints "fake.el"))
           (parsed (json-read-from-string json)))
      (should (= 2 (length parsed)))
      (let ((h0 (aref parsed 0))
            (h1 (aref parsed 1)))
        (should (= 5    (alist-get 'line h0)))
        (should (= 8    (alist-get 'column h0)))
        (should (string= "type"      (alist-get 'kind h0)))
        (should (string= ": i32"     (alist-get 'label h0)))
        (should (= 8    (alist-get 'line h1)))
        (should (string= "parameter" (alist-get 'kind h1)))
        (should (string= "value:"    (alist-get 'label h1)))))))

(ert-deftest lsp-mcp-test-inlay-hints-vector-label ()
  "Label as InlayHintLabelPart[] is concatenated."
  (lsp-mcp-test--with-lsp-request
      (vector
       (list :position (list :line 0 :character 0)
             :kind 1
             :label (vector (list :value ": ") (list :value "String"))))
    (let* ((json (lsp-mcp--inlay-hints "fake.el"))
           (parsed (json-read-from-string json)))
      (should (string= ": String" (alist-get 'label (aref parsed 0)))))))

(ert-deftest lsp-mcp-test-inlay-hints-nil-response ()
  (lsp-mcp-test--with-lsp-request nil
    (should (string= "[]" (lsp-mcp--inlay-hints "fake.el")))))

(ert-deftest lsp-mcp-test-inlay-hints-unknown-kind ()
  (lsp-mcp-test--with-lsp-request
      (vector (list :position (list :line 0 :character 0)
                    :kind 99
                    :label "?"))
    (let* ((json (lsp-mcp--inlay-hints "fake.el"))
           (parsed (json-read-from-string json)))
      (should (string= "other" (alist-get 'kind (aref parsed 0)))))))


;;; document highlight formatting

(ert-deftest lsp-mcp-test-document-highlight-basic ()
  (lsp-mcp-test--with-lsp-request
      (vector
       (list :range (list :start (list :line 2 :character 4)
                          :end   (list :line 2 :character 9))
             :kind 2)  ; read
       (list :range (list :start (list :line 5 :character 0)
                          :end   (list :line 5 :character 5))
             :kind 3)) ; write
    (let* ((json (lsp-mcp--document-highlight "fake.el" 2 4))
           (parsed (json-read-from-string json)))
      (should (= 2 (length parsed)))
      (let ((h0 (aref parsed 0))
            (h1 (aref parsed 1)))
        (should (string= "read"  (alist-get 'kind h0)))
        (should (= 3             (alist-get 'line h0)))
        (should (= 4             (alist-get 'column h0)))
        (should (= 3             (alist-get 'end-line h0)))
        (should (= 9             (alist-get 'end-column h0)))
        (should (string= "write" (alist-get 'kind h1)))
        (should (= 6             (alist-get 'line h1)))))))

(ert-deftest lsp-mcp-test-document-highlight-no-kind-defaults-text ()
  "Missing :kind field defaults to \"text\"."
  (lsp-mcp-test--with-lsp-request
      (vector
       (list :range (list :start (list :line 0 :character 0)
                          :end   (list :line 0 :character 3))))
    (let* ((json (lsp-mcp--document-highlight "fake.el" 1 0))
           (parsed (json-read-from-string json)))
      (should (string= "text" (alist-get 'kind (aref parsed 0)))))))

(ert-deftest lsp-mcp-test-document-highlight-nil-response ()
  (lsp-mcp-test--with-lsp-request nil
    (should (string= "[]" (lsp-mcp--document-highlight "fake.el" 1 0)))))


;;; call-hierarchy JSON shape

(ert-deftest lsp-mcp-test-call-hierarchy-nil-prepare ()
  "prepareCallHierarchy returning nil → empty array."
  (cl-letf (((symbol-function 'lsp-request)
             (lambda (method _params)
               (when (string= method "textDocument/prepareCallHierarchy") nil)))
            ((symbol-function 'lsp-mcp--ensure-lsp-buffer)
             (lambda (_file) (current-buffer))))
    (should (string= "[]" (lsp-mcp--call-hierarchy "fake.el" 1 0 "incoming")))))

(ert-deftest lsp-mcp-test-call-hierarchy-incoming-shape ()
  (let* ((callee-item (list :name "target-fn" :kind 12
                            :uri "file:///b.el"
                            :range (list :start (list :line 9 :character 0)
                                         :end   (list :line 9 :character 9))))
         (caller-item (list :name "caller-fn" :kind 12
                            :uri "file:///a.el"
                            :range (list :start (list :line 4 :character 0)
                                         :end   (list :line 4 :character 9))))
         (incoming-call (list :from caller-item
                              :fromRanges (vector
                                           (list :start (list :line 5 :character 2)
                                                 :end   (list :line 5 :character 11))))))
    (cl-letf (((symbol-function 'lsp-request)
               (lambda (method _params)
                 (cond
                  ((string= method "textDocument/prepareCallHierarchy")
                   (vector callee-item))
                  ((string= method "callHierarchy/incomingCalls")
                   (vector incoming-call)))))
              ((symbol-function 'lsp-mcp--ensure-lsp-buffer)
               (lambda (_file) (current-buffer))))
      (let* ((json (lsp-mcp--call-hierarchy "fake.el" 10 0 "incoming"))
             (parsed (json-read-from-string json))
             (entry (aref parsed 0)))
        (should (= 1 (length parsed)))
        (should (string= "caller-fn"  (alist-get 'name entry)))
        (should (string= "/a.el"      (alist-get 'file entry)))
        (should (= 5                  (alist-get 'line entry)))
        ;; call-sites: fromRanges line 5 (0-indexed) → 6 (1-indexed)
        (should (equal [6] (alist-get 'call-sites entry)))))))

(ert-deftest lsp-mcp-test-call-hierarchy-outgoing-shape ()
  (let* ((caller-item (list :name "my-fn" :kind 12
                            :uri "file:///a.el"
                            :range (list :start (list :line 0 :character 0)
                                         :end   (list :line 0 :character 4))))
         (callee-item (list :name "helper" :kind 12
                            :uri "file:///b.el"
                            :range (list :start (list :line 19 :character 0)
                                         :end   (list :line 19 :character 6))))
         (outgoing-call (list :to callee-item
                              :fromRanges (vector
                                           (list :start (list :line 2 :character 4)
                                                 :end   (list :line 2 :character 10))))))
    (cl-letf (((symbol-function 'lsp-request)
               (lambda (method _params)
                 (cond
                  ((string= method "textDocument/prepareCallHierarchy")
                   (vector caller-item))
                  ((string= method "callHierarchy/outgoingCalls")
                   (vector outgoing-call)))))
              ((symbol-function 'lsp-mcp--ensure-lsp-buffer)
               (lambda (_file) (current-buffer))))
      (let* ((json (lsp-mcp--call-hierarchy "fake.el" 1 0 "outgoing"))
             (parsed (json-read-from-string json))
             (entry (aref parsed 0)))
        (should (= 1 (length parsed)))
        (should (string= "helper" (alist-get 'name entry)))
        (should (string= "/b.el"  (alist-get 'file entry)))
        ;; call-sites: fromRanges line 2 (0-indexed) → 3 (1-indexed)
        (should (equal [3] (alist-get 'call-sites entry)))))))


;;; Formatting helpers

(ert-deftest lsp-mcp-test-line-col-to-pos-first-line ()
  (with-temp-buffer
    (insert "hello\nworld\n")
    (should (= 1 (lsp-mcp--line-col-to-pos 1 0)))
    (should (= 3 (lsp-mcp--line-col-to-pos 1 2)))))

(ert-deftest lsp-mcp-test-line-col-to-pos-second-line ()
  (with-temp-buffer
    (insert "hello\nworld\n")
    ;; "hello\n" = 6 chars; line 2, col 0 = position 7
    (should (= 7 (lsp-mcp--line-col-to-pos 2 0)))
    (should (= 9 (lsp-mcp--line-col-to-pos 2 2)))))

(ert-deftest lsp-mcp-test-format-buffer-calls-lsp-format-buffer ()
  "lsp-mcp--format-buffer must call lsp-format-buffer and save-buffer."
  (let (format-called save-called)
    (cl-letf (((symbol-function 'lsp-mcp--ensure-lsp-buffer)
               (lambda (_file) (current-buffer)))
              ((symbol-function 'lsp-format-buffer)
               (lambda () (setq format-called t)))
              ((symbol-function 'save-buffer)
               (lambda (&rest _) (setq save-called t))))
      (should (string= "formatted" (lsp-mcp--format-buffer "fake.el")))
      (should format-called)
      (should save-called))))

(ert-deftest lsp-mcp-test-format-region-calls-lsp-format-region ()
  "lsp-mcp--format-region must call lsp-format-region with correct positions and save."
  (let (region-start region-end save-called)
    (cl-letf (((symbol-function 'lsp-mcp--ensure-lsp-buffer)
               (lambda (_file) (current-buffer)))
              ((symbol-function 'lsp-format-region)
               (lambda (s e) (setq region-start s region-end e)))
              ((symbol-function 'save-buffer)
               (lambda (&rest _) (setq save-called t))))
      (with-temp-buffer
        (insert "line one\nline two\nline three\n")
        (should (string= "formatted"
                         (lsp-mcp--format-region "fake.el" 2 5 2 8)))
        (should save-called)
        ;; line 2, col 5 = position 15 ("line one\n" = 9 + 5 = 14 → 1-indexed = 15)
        (should (= 15 region-start))
        ;; line 2, col 8 = position 18
        (should (= 18 region-end))))))

(ert-deftest lsp-mcp-test-format-region-string-params ()
  "start-line/end-line/col params may arrive as strings — must parse."
  (let (region-start)
    (cl-letf (((symbol-function 'lsp-mcp--ensure-lsp-buffer)
               (lambda (_file) (current-buffer)))
              ((symbol-function 'lsp-format-region)
               (lambda (s _e) (setq region-start s)))
              ((symbol-function 'save-buffer)
               (lambda (&rest _))))
      (with-temp-buffer
        (insert "abc\ndef\n")
        (lsp-mcp--format-region "fake.el" "2" "0" "2" "3")
        ;; "abc\n" = 4 chars; line 2 col 0 = position 5
        (should (= 5 region-start))))))


(provide 'lsp-mcp-test)

;;; lsp-mcp-test.el ends here
