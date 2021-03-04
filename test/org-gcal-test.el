;;; org-gcal-test.el --- Tests for org-gcal.el -*- lexical-binding: t -*-

;; Copyright (C) 2019 Robert Irelan
;; Package-Requires: ((org-gcal) (el-mock))

;; Author: Robert Irelan <rirelan@gmail.com>

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; Tests for org-gcal.el

;;; Code:

(require 'org-gcal)
(require 'cl-lib)
(require 'el-mock)

(defconst org-gcal-test-calendar-id "foo@foobar.com")

(defconst org-gcal-test-event-json
  "\
{
 \"kind\": \"calendar#event\",
 \"etag\": \"\\\"12344321\\\"\",
 \"id\": \"foobar1234\",
 \"status\": \"confirmed\",
 \"htmlLink\": \"https://www.google.com/calendar/event?eid=foobareid1234\",
 \"hangoutsLink\": \"https://hangouts.google.com/my-meeting-id\",
 \"location\": \"Foobar's desk\",
 \"created\": \"2019-09-27T20:50:45.000Z\",
 \"updated\": \"2019-10-06T22:59:47.287Z\",
 \"summary\": \"My event summary\",
 \"description\": \"My event description\\n\\nSecond paragraph\",
 \"creator\": {
  \"email\": \"foo@foobar.com\",
  \"displayName\": \"Foo Foobar\"
 },
 \"organizer\": {
  \"email\": \"bar@foobar.com\",
  \"self\": true
 },
 \"start\": {
  \"dateTime\": \"2019-10-06T17:00:00-07:00\"
 },
 \"end\": {
  \"dateTime\": \"2019-10-06T21:00:00-07:00\"
 },
 \"reminders\": {
  \"useDefault\": true
 }
}
")

(defconst org-gcal-test-cancelled-event-json
  (replace-regexp-in-string "confirmed" "cancelled"
                            org-gcal-test-event-json))

(defmacro org-gcal-test--with-temp-buffer (contents &rest body)
  "Create a ‘org-mode’ enabled temp buffer with CONTENTS.
BODY is code to be executed within the temp buffer.  Point is
always located at the beginning of the buffer."
  (declare (indent 1) (debug t))
  `(with-temp-buffer
     (org-mode)
     (insert ,contents)
     (goto-char (point-min))
     ,@body))

(defun org-gcal-test--json-read-string (json)
  "Wrap ‘org-gcal--json-read’ to parse a JSON string"
  (with-temp-buffer
    (insert json)
    (org-gcal--json-read)))

(defconst org-gcal-test-event
  (org-gcal-test--json-read-string org-gcal-test-event-json))

(defconst org-gcal-test-cancelled-event
  (org-gcal-test--json-read-string org-gcal-test-cancelled-event-json))

(ert-deftest org-gcal-test--save-sexp ()
  "Verify that org-gcal--save-sexp saves its data to the right place."
  (let* ((file (make-temp-file "org-gcal-test--save-sexp.")))
    (unwind-protect
        (org-gcal-test--with-temp-buffer
         ""
         (let ((data '(:foo :bar)))
           (org-gcal--save-sexp data file)
           (should (equal (buffer-string)
                          ""))
           (should (equal (org-gcal--read-file-contents file)
                          `(:token ,data :elem nil)))
           (setq data '(:baz :quux))
           (org-gcal--save-sexp data file)
           (should (equal (buffer-string)
                          ""))
           (should (equal (org-gcal--read-file-contents file)
                          `(:token ,data :elem nil))))))))

(ert-deftest org-gcal-test--update-empty-entry ()
  "Verify that an empty headline is populated correctly from a calendar event
object."
  (org-gcal-test--with-temp-buffer
   "* "
   (org-gcal--update-entry org-gcal-test-calendar-id
                           org-gcal-test-event)
   (org-back-to-heading)
   (let ((elem (org-element-at-point)))
     (should (equal (org-element-property :title elem)
                    "My event summary"))
     (should (equal (org-element-property :ETAG elem)
                    "\"12344321\""))
     (should (equal (org-element-property :LOCATION elem)
                    "Foobar's desk"))
     (should (equal (org-element-property :CALENDAR-ID elem)
                    "foo@foobar.com"))
     (should (equal (org-element-property :ENTRY-ID elem)
                    "foobar1234/foo@foobar.com")))
   ;; Check contents of "org-gcal" drawer
   (re-search-forward ":org-gcal:")
   (let ((elem (org-element-at-point)))
     (should (equal (org-element-property :drawer-name elem)
                    "org-gcal"))
     (should (equal (buffer-substring-no-properties
                     (org-element-property :contents-begin elem)
                     (org-element-property :contents-end elem))
                    "\
<2019-10-06 Sun 17:00-21:00>

My event description

Second paragraph
")))))

(ert-deftest org-gcal-test--update-existing-entry ()
  "Verify that an existing headline is populated correctly from a calendar event
object."
  (org-gcal-test--with-temp-buffer
   "\
* Old event summary
:PROPERTIES:
:ETag:     \"9999\"
:LOCATION: Somewhere else
:calendar-id: foo@foobar.com
:entry-id:       foobar1234/foo@foobar.com
:END:
:org-gcal:
<9999-10-06 Sun 17:00-21:00>

Old event description
:END:
"
   (org-gcal--update-entry org-gcal-test-calendar-id
                           org-gcal-test-event)
   (org-back-to-heading)
   (let ((elem (org-element-at-point)))
     (should (equal (org-element-property :title elem)
                    "My event summary"))
     (should (equal (org-element-property :ETAG elem)
                    "\"12344321\""))
     (should (equal (org-element-property :LOCATION elem)
                    "Foobar's desk"))
     (should (equal (org-element-property :CALENDAR-ID elem)
                    "foo@foobar.com"))
     (should (equal (org-element-property :ENTRY-ID elem)
                    "foobar1234/foo@foobar.com")))
   ;; Check contents of "org-gcal" drawer
   (re-search-forward ":org-gcal:")
   (let ((elem (org-element-at-point)))
     (should (equal (org-element-property :drawer-name elem)
                    "org-gcal"))
     (should (equal (buffer-substring-no-properties
                     (org-element-property :contents-begin elem)
                     (org-element-property :contents-end elem))
                    "\
<2019-10-06 Sun 17:00-21:00>

My event description

Second paragraph
")))))

(ert-deftest org-gcal-test--update-existing-entry-cancelled ()
  "Verify that an existing headline is populated correctly from a cancelled
  calendar event object."
  (let (
        (org-todo-keywords '((sequence "TODO" "|" "DONE" "CANCELLED")))
        (org-gcal-cancelled-todo-keyword "CANCELLED")
        (org-gcal-remove-api-cancelled-events nil)
        (buf "\
* Old event summary
:PROPERTIES:
:ETag:     \"9999\"
:LOCATION: Somewhere else
:calendar-id: foo@foobar.com
:entry-id:       foobar1234/foo@foobar.com
:END:
:org-gcal:
<9999-10-06 Sun 17:00-21:00>

Old event description
:END:
"))
    (let ((org-gcal-update-cancelled-events-with-todo t))
      (org-gcal-test--with-temp-buffer
       buf
       (org-gcal--update-entry org-gcal-test-calendar-id
                               org-gcal-test-cancelled-event)
       (org-back-to-heading)
       (let ((elem (org-element-at-point)))
         (should (equal (org-element-property :title elem)
                        "My event summary"))
         (should (equal (org-element-property :todo-keyword elem)
                        "CANCELLED"))
         (should (equal (org-element-property :ETAG elem)
                        "\"12344321\""))
         (should (equal (org-element-property :LOCATION elem)
                        "Foobar's desk"))
         (should (equal (org-element-property :CALENDAR-ID elem)
                        "foo@foobar.com"))
         (should (equal (org-element-property :ENTRY-ID elem)
                        "foobar1234/foo@foobar.com")))
       ;; Check contents of "org-gcal" drawer
       (re-search-forward ":org-gcal:")
       (let ((elem (org-element-at-point)))
         (should (equal (org-element-property :drawer-name elem)
                        "org-gcal"))
         (should (equal (buffer-substring-no-properties
                         (org-element-property :contents-begin elem)
                         (org-element-property :contents-end elem))
                        "\
<2019-10-06 Sun 17:00-21:00>

My event description

Second paragraph
")))))
    (let ((org-gcal-update-cancelled-events-with-todo nil))
      (org-gcal-test--with-temp-buffer
       buf
       (org-gcal--update-entry org-gcal-test-calendar-id
                               org-gcal-test-cancelled-event)
       (org-back-to-heading)
       (let ((elem (org-element-at-point)))
         (should (equal (org-element-property :title elem)
                        "My event summary"))
         (should (equal (org-element-property :todo-keyword elem)
                        nil))
         (should (equal (org-element-property :ETAG elem)
                        "\"12344321\""))
         (should (equal (org-element-property :LOCATION elem)
                        "Foobar's desk"))
         (should (equal (org-element-property :CALENDAR-ID elem)
                        "foo@foobar.com"))
         (should (equal (org-element-property :ENTRY-ID elem)
                        "foobar1234/foo@foobar.com")))
       ;; Check contents of "org-gcal" drawer
       (re-search-forward ":org-gcal:")
       (let ((elem (org-element-at-point)))
         (should (equal (org-element-property :drawer-name elem)
                        "org-gcal"))
         (should (equal (buffer-substring-no-properties
                         (org-element-property :contents-begin elem)
                         (org-element-property :contents-end elem))
                        "\
<2019-10-06 Sun 17:00-21:00>

My event description

Second paragraph
")))))
    (let ((org-gcal-remove-api-cancelled-events t))
      (org-gcal-test--with-temp-buffer
       buf
       (org-gcal--update-entry org-gcal-test-calendar-id
                               org-gcal-test-cancelled-event)
       (should (equal (buffer-substring-no-properties
                       (point-min) (point-max))
                      ""))))))

(ert-deftest org-gcal-test--update-existing-entry-already-cancelled ()
  "Verify that an existing headline is modified correctly according to the \
  value of ‘org-gcal-remove-events-with-cancelled-todo’."
  (let (
        (org-todo-keywords '((sequence "TODO" "|" "DONE" "CANCELLED")))
        (org-gcal-cancelled-todo-keyword "CANCELLED")
        (org-gcal-remove-api-cancelled-events nil)
        (org-gcal-remove-events-with-cancelled-todo nil)
        (buf "\
* Old event summary
:PROPERTIES:
:ETag:     \"9999\"
:LOCATION: Somewhere else
:calendar-id: foo@foobar.com
:entry-id:       foobar1234/foo@foobar.com
:END:
:org-gcal:
<9999-10-06 Sun 17:00-21:00>

Old event description
:END:
"))
    (let ((org-gcal-update-cancelled-events-with-todo t))
      (org-gcal-test--with-temp-buffer
       buf
       ;; First mark the event as cancelled.
       (org-gcal--update-entry org-gcal-test-calendar-id
                               org-gcal-test-cancelled-event)
       (org-back-to-heading)
       (let ((elem (org-element-at-point)))
         (should (equal (org-element-property :title elem)
                        "My event summary"))
         (should (equal (org-element-property :todo-keyword elem)
                        "CANCELLED"))
         (should (equal (org-element-property :ETAG elem)
                        "\"12344321\""))
         (should (equal (org-element-property :LOCATION elem)
                        "Foobar's desk"))
         (should (equal (org-element-property :CALENDAR-ID elem)
                        "foo@foobar.com"))
         (should (equal (org-element-property :ENTRY-ID elem)
                        "foobar1234/foo@foobar.com")))
       ;; Check contents of "org-gcal" drawer
       (re-search-forward ":org-gcal:")
       (let ((elem (org-element-at-point)))
         (should (equal (org-element-property :drawer-name elem)
                        "org-gcal"))
         (should (equal (buffer-substring-no-properties
                         (org-element-property :contents-begin elem)
                         (org-element-property :contents-end elem))
                        "\
<2019-10-06 Sun 17:00-21:00>

My event description

Second paragraph
")))
       ;; Now check that the event isn’t removed when
       ;; ‘org-gcal-remove-events-with-cancelled-todo’ is nil.
       (setq org-gcal-remove-api-cancelled-events t
             org-gcal-remove-events-with-cancelled-todo nil)
       (org-back-to-heading)
       (org-gcal--update-entry org-gcal-test-calendar-id
                               org-gcal-test-cancelled-event)
       (org-back-to-heading)
       (let ((elem (org-element-at-point)))
         (should (equal (org-element-property :title elem)
                        "My event summary"))
         (should (equal (org-element-property :todo-keyword elem)
                        "CANCELLED"))
         (should (equal (org-element-property :ETAG elem)
                        "\"12344321\""))
         (should (equal (org-element-property :LOCATION elem)
                        "Foobar's desk"))
         (should (equal (org-element-property :CALENDAR-ID elem)
                        "foo@foobar.com"))
         (should (equal (org-element-property :ENTRY-ID elem)
                        "foobar1234/foo@foobar.com")))
       ;; Check contents of "org-gcal" drawer
       (re-search-forward ":org-gcal:")
       (let ((elem (org-element-at-point)))
         (should (equal (org-element-property :drawer-name elem)
                        "org-gcal"))
         (should (equal (buffer-substring-no-properties
                         (org-element-property :contents-begin elem)
                         (org-element-property :contents-end elem))
                        "\
<2019-10-06 Sun 17:00-21:00>

My event description

Second paragraph
")))
       ;; Now check that the event is removed when
       ;; ‘org-gcal-remove-events-with-cancelled-todo’ is t.
       (setq org-gcal-remove-api-cancelled-events t
             org-gcal-remove-events-with-cancelled-todo t)
       (org-back-to-heading)
       (org-gcal--update-entry org-gcal-test-calendar-id
                               org-gcal-test-cancelled-event)
       (should (equal (buffer-substring-no-properties
                       (point-min) (point-max))
                      ""))))))

(ert-deftest org-gcal-test--update-existing-entry-scheduled ()
  "Same as ‘org-gcal-test--update-existing-entry’, but with SCHEDULED
property."
  (org-gcal-test--with-temp-buffer
      "\
* Old event summary
SCHEDULED: <9999-10-06 Sun 17:00-21:00>
:PROPERTIES:
:ETag:     \"9999\"
:LOCATION: Somewhere else
:calendar-id: foo@foobar.com
:entry-id:       foobar1234/foo@foobar.com
:END:
:org-gcal:
Old event description
:END:
"
    (org-gcal--update-entry org-gcal-test-calendar-id
                            org-gcal-test-event)
    (org-back-to-heading)
    (let ((elem (org-element-at-point)))
      (should (equal (org-element-property
                      :raw-value
                      (org-element-property :scheduled elem))
                     "<2019-10-06 Sun 17:00-21:00>"))
      (should (equal (org-element-property :title elem)
                     "My event summary"))
      (should (equal (org-element-property :ETAG elem)
                     "\"12344321\""))
      (should (equal (org-element-property :LOCATION elem)
                     "Foobar's desk"))
      (should (equal (org-element-property :CALENDAR-ID elem)
                     "foo@foobar.com"))
      (should (equal (org-element-property :ENTRY-ID elem)
                     "foobar1234/foo@foobar.com")))
    ;; Check contents of "org-gcal" drawer
    (re-search-forward ":org-gcal:")
    (let ((elem (org-element-at-point)))
      (should (equal (org-element-property :drawer-name elem)
                     "org-gcal"))
      (should (equal (buffer-substring-no-properties
                      (org-element-property :contents-begin elem)
                      (org-element-property :contents-end elem))
                     "\
My event description

Second paragraph
")))))

(ert-deftest org-gcal-test--update-existing-entry-with-id ()
  "Verify that existing IDs in an existing headline will be preserved."
  (org-gcal-test--with-temp-buffer
      "\
* Old event summary
:PROPERTIES:
:LOCATION: Somewhere else
:calendar-id: foo@foobar.com
:entry-id:       ABCD-EFGH
:END:
:org-gcal:
<9999-10-06 Sun 17:00-21:00>

Old event description
:END:
"
    (org-gcal--update-entry org-gcal-test-calendar-id
                            org-gcal-test-event)
    (org-back-to-heading)
    (let ((elem (org-element-at-point)))
      (should (equal (org-element-property :title elem)
                     "My event summary"))
      (should (equal (org-element-property :ETAG elem)
                     "\"12344321\""))
      (should (equal (org-element-property :LOCATION elem)
                     "Foobar's desk"))
      (should (equal (org-element-property :CALENDAR-ID elem)
                     "foo@foobar.com")))
    ;; The canonical ID should be that generated by org-gcal.
    (should (equal (org-gcal--all-property-local-values (point) org-gcal-entry-id-property nil)
                   '("foobar1234/foo@foobar.com")))
    (should (equal (org-entry-get (point) org-gcal-entry-id-property)
                   '"foobar1234/foo@foobar.com"))
    ;; Check contents of "org-gcal" drawer
    (re-search-forward ":org-gcal:")
    (let ((elem (org-element-at-point)))
      (should (equal (org-element-property :drawer-name elem)
                     "org-gcal"))
      (should (equal (buffer-substring-no-properties
                      (org-element-property :contents-begin elem)
                      (org-element-property :contents-end elem))
                     "\
<2019-10-06 Sun 17:00-21:00>

My event description

Second paragraph
")))))

(ert-deftest org-gcal-test--post-at-point-basic ()
  "Verify basic case of ‘org-gcal-post-to-point’."
  (org-gcal-test--with-temp-buffer
      "\
* My event summary
:PROPERTIES:
:ETag:     \"12344321\"
:LOCATION: Foobar's desk
:calendar-id: foo@foobar.com
:entry-id:       foobar1234/foo@foobar.com
:END:
:org-gcal:
<2019-10-06 Sun 17:00-21:00>

My event description

Second paragraph
:END:
"
    (with-mock
      (stub org-gcal--time-zone => '(0 "UTC"))
      (stub org-generic-id-add-location => nil)
      (stub org-gcal-request-token => (deferred:succeed nil))
      (mock (org-gcal--post-event "2019-10-06T17:00:00Z" "2019-10-06T21:00:00Z"
                                  "My event summary" "Foobar's desk"
                                  "My event description\n\nSecond paragraph"
                                  "foo@foobar.com"
                                  * "\"12344321\"" "foobar1234"
                                  * * *))
      (org-gcal-post-at-point))))

(ert-deftest org-gcal-test--post-at-point-old-id-property ()
  "Verify that \":ID:\" property is read for event ID by \
‘org-gcal-post-to-point’ only if ‘org-gcal-entry-id-property’ is not present."
  (org-gcal-test--with-temp-buffer
      "\
* My event summary
:PROPERTIES:
:ETag:     \"12344321\"
:LOCATION: Foobar's desk
:calendar-id: foo@foobar.com
:ID:       foobar1234/foo@foobar.com
:END:
:org-gcal:
<2019-10-06 Sun 17:00-21:00>

My event description

Second paragraph
:END:
"
    (with-mock
      (stub org-gcal--time-zone => '(0 "UTC"))
      (stub org-generic-id-add-location => nil)
      (stub org-gcal-request-token => (deferred:succeed nil))
      (mock (org-gcal--post-event "2019-10-06T17:00:00Z" "2019-10-06T21:00:00Z"
                                  "My event summary" "Foobar's desk"
                                  "My event description\n\nSecond paragraph"
                                  "foo@foobar.com"
                                  * "\"12344321\"" "foobar1234"
                                  * * *))
      (org-gcal-post-at-point)))
  (org-gcal-test--with-temp-buffer
      "\
* My event summary
:PROPERTIES:
:ETag:     \"12344321\"
:LOCATION: Foobar's desk
:calendar-id: foo@foobar.com
:ID:             hello-world
:entry-id:       foobar1234/foo@foobar.com
:END:
:org-gcal:
<2019-10-06 Sun 17:00-21:00>

My event description

Second paragraph
:END:
"
    (with-mock
      (stub org-gcal--time-zone => '(0 "UTC"))
      (stub org-generic-id-add-location => nil)
      (stub org-gcal-request-token => (deferred:succeed nil))
      (mock (org-gcal--post-event "2019-10-06T17:00:00Z" "2019-10-06T21:00:00Z"
                                  "My event summary" "Foobar's desk"
                                  "My event description\n\nSecond paragraph"
                                  "foo@foobar.com"
                                  * "\"12344321\"" "foobar1234"
                                  * * *))
      (org-gcal-post-at-point))))


(ert-deftest org-gcal-test--post-at-point-no-id ()
  "Verify that ‘org-gcal-post-to-point’ doesn't send an ID to Calendar API if
an org-gcal Calendar Event ID can't be retrieved from the current entry."
  (org-gcal-test--with-temp-buffer
      "\
* My event summary
:PROPERTIES:
:LOCATION: Foobar's desk
:calendar-id: foo@foobar.com
:END:
:org-gcal:
<2019-10-06 Sun 17:00-21:00>

My event description

Second paragraph
:END:
"
    (with-mock
      (stub org-gcal--time-zone => '(0 "UTC"))
      (stub org-generic-id-add-location => nil)
      (stub org-gcal-request-token => (deferred:succeed nil))
      (mock (org-gcal--post-event "2019-10-06T17:00:00Z" "2019-10-06T21:00:00Z"
                                  "My event summary" "Foobar's desk"
                                  "My event description\n\nSecond paragraph"
                                  "foo@foobar.com"
                                  * nil nil
                                  * * *))
      (org-gcal-post-at-point)))
  (org-gcal-test--with-temp-buffer
      "\
* My event summary
:PROPERTIES:
:LOCATION: Foobar's desk
:calendar-id: foo@foobar.com
:entry-id: ABCD-EFGH
:END:
:org-gcal:
<2019-10-06 Sun 17:00-21:00>

My event description

Second paragraph
:END:
"
    (with-mock
      (stub org-gcal--time-zone => '(0 "UTC"))
      (stub org-generic-id-add-location => nil)
      (stub org-gcal-request-token => (deferred:succeed nil))
      (mock (org-gcal--post-event "2019-10-06T17:00:00Z" "2019-10-06T21:00:00Z"
                                  "My event summary" "Foobar's desk"
                                  "My event description\n\nSecond paragraph"
                                  "foo@foobar.com"
                                  * nil nil
                                  * * *))
      (org-gcal-post-at-point))))

(ert-deftest org-gcal-test--post-at-point-no-properties ()
  "Verify that ‘org-gcal-post-to-point’ fills in entries with no relevant
org-gcal properties with sane default values."
  (org-gcal-test--with-temp-buffer
   "\
* My event summary
"
   (with-mock
    (stub completing-read => "foo@foobar.com")
    (stub org-read-date => (encode-time 0 0 17 6 10 2019 nil nil t))
    (stub read-from-minibuffer => "4:00")
    (stub org-gcal--time-zone => '(0 "UTC"))
    (stub org-generic-id-add-location => nil)
    (stub org-gcal-request-token => (deferred:succeed nil))
    (mock (org-gcal--post-event "2019-10-06T17:00:00+0000" "2019-10-06T21:00:00+0000"
                                "My event summary" nil
                                nil
                                "foo@foobar.com"
                                * nil nil
                                * * *))
    (org-gcal-post-at-point)))
  (org-gcal-test--with-temp-buffer
   "\
* My event summary
:PROPERTIES:
:Effort: 2:00
:END:
:LOGBOOK:
CLOCK: [2019-06-06 Thu 17:00]--[2019-06-06 Thu 18:00] => 1:00
:END:
"
   (with-mock
    (stub completing-read => "foo@foobar.com")
    (stub org-read-date => (encode-time 0 0 17 6 10 2019 nil nil t))
    (stub org-gcal--time-zone => '(0 "UTC"))
    (stub org-generic-id-add-location => nil)
    (stub org-gcal-request-token => (deferred:succeed nil))
    (cl-letf
        (((symbol-function #'read-from-minibuffer)
          (lambda (_p initial-contents) initial-contents)))
      (mock (org-gcal--post-event "2019-10-06T17:00:00+0000" "2019-10-06T18:00:00+0000"
                                  "My event summary" nil
                                  nil
                                  "foo@foobar.com"
                                  * nil nil
                                  * * *))
      (org-gcal-post-at-point)))))

(ert-deftest org-gcal-test--post-at-point-etag-no-id ()
  "Verify that ‘org-gcal-post-to-point’ fails if an ETag is present but
an event ID is not."
  :expected-result :failed
  (org-gcal-test--with-temp-buffer
      "\
* My event summary
:PROPERTIES:
:LOCATION: Foobar's desk
:ETag:     \"12344321\"
:calendar-id: foo@foobar.com
:END:
:org-gcal:
<2019-10-06 Sun 17:00-21:00>

My event description

Second paragraph
:END:
"
    (with-mock
      (stub org-gcal--time-zone => '(0 "UTC"))
      (stub org-generic-id-add-location => nil)
      (stub org-gcal-request-token => (deferred:succeed nil))
      (stub request-deferred => (deferred:succeed nil))
      (org-gcal-post-at-point))))

(ert-deftest org-gcal-test--post-at-point-time-date-range ()
  "Verify that entry with a time/date range for its timestamp is parsed by
‘org-gcal-post-to-point’ (see https://orgmode.org/manual/Timestamps.html)."
  (org-gcal-test--with-temp-buffer
      "\
* My event summary
SCHEDULED: <2019-10-06 Sun 17:00>--<2019-10-07 Mon 21:00>
:PROPERTIES:
:ETag:     \"12344321\"
:LOCATION: Foobar's desk
:calendar-id: foo@foobar.com
:entry-id:       foobar1234/foo@foobar.com
:END:
:org-gcal:
My event description

Second paragraph
:END:
"
    (with-mock
      (stub org-gcal--time-zone => '(0 "UTC"))
      (stub org-generic-id-add-location => nil)
      (stub org-gcal-request-token => (deferred:succeed nil))
      (mock (org-gcal--post-event "2019-10-06T17:00:00Z" "2019-10-07T21:00:00Z"
                                  "My event summary" "Foobar's desk"
                                  "My event description\n\nSecond paragraph"
                                  "foo@foobar.com"
                                  * "\"12344321\"" "foobar1234"
                                  * * *))
      (org-gcal-post-at-point))))

(ert-deftest org-gcal-test--delete-at-point-delete-drawer ()
  "Verify that the org-gcal drawer is deleted by ‘org-gcal-delete-at-point’ if
and only if the event at the point is successfully deleted by the Google
Calendar API."
  (let ((org-gcal-remove-api-cancelled-events nil)
        (org-gcal-update-cancelled-events-with-todo nil)
        (buf "\
* My event summary
SCHEDULED: <2019-10-06 Sun 17:00>--<2019-10-07 Mon 21:00>
:PROPERTIES:
:ETag:     \"12344321\"
:LOCATION: Foobar's desk
:calendar-id: foo@foobar.com
:entry-id:       foobar1234/foo@foobar.com
:END:
:org-gcal:
My event description

Second paragraph
:END:
"))
    (org-gcal-test--with-temp-buffer
     buf
     ;; Don’t delete drawer if we don’t receive 200.
     (with-mock
      (let ((deferred:debug t))
        (stub org-gcal--time-zone => '(0 "UTC")))
      (stub org-generic-id-add-location => nil)
      (stub org-gcal-request-token => (deferred:succeed nil))
      (stub y-or-n-p => t)
      (stub alert => t)
      (stub request-deferred =>
            (deferred:succeed
              (make-request-response
               :status-code 500
               :error-thrown '(error . nil))))
      (deferred:sync!
        (deferred:$
          (org-gcal-delete-at-point)
          (deferred:error it #'ignore)))
      (org-back-to-heading)
      (should (re-search-forward ":org-gcal:" nil 'noerror))))

    ;; Delete drawer if we do receive 200.
    (org-gcal-test--with-temp-buffer
     buf
     (with-mock
      (let ((deferred:debug t))
        (stub org-gcal--time-zone => '(0 "UTC"))
        (stub org-generic-id-add-location => nil)
        (stub org-gcal-request-token => (deferred:succeed nil))
        (stub y-or-n-p => t)
        (stub request-deferred =>
              (deferred:succeed
                (make-request-response
                 :status-code 200)))
        (deferred:sync! (org-gcal-delete-at-point))
        (org-back-to-heading)
        (should-not (re-search-forward ":org-gcal:" nil 'noerror)))))

    ;; Delete the entire entry if configured to
    (org-gcal-test--with-temp-buffer
     buf
     (with-mock
      (let ((deferred:debug t)
            (org-gcal-remove-api-cancelled-events t))
        (stub org-gcal--time-zone => '(0 "UTC"))
        (stub org-gcal-request-token => (deferred:succeed nil))
        (stub y-or-n-p => t)
        (stub request-deferred =>
              (deferred:succeed
                (make-request-response
                 :status-code 200)))
        (deferred:sync! (org-gcal-delete-at-point))
        (should (equal (buffer-string) "")))))))

(ert-deftest org-gcal-test--ert-fail ()
  "Test handling of ERT failures in deferred code. Should fail."
  :expected-result :failed
  (with-mock
    (stub request-deferred =>
          (deferred:$
            (deferred:succeed
              (ert-fail "Failure"))
            (deferred:nextc it
              (lambda (_)
                (deferred:succeed "Success")))))
    (should (equal
             (deferred:sync! (request-deferred))
             "Success"))))

(ert-deftest org-gcal-test--convert-time-to-local-timezone()
  (should (equal
           (convert-time-to-local-timezone "2021-03-03T11:30:00-00:00" nil)
           "2021-03-03T11:30:00-00:00"))
  (should (equal
           (convert-time-to-local-timezone "2021-03-03T11:30:00-00:00" "")
           "2021-03-03T11:30:00+0000"))
  (should (equal
           (convert-time-to-local-timezone "2021-03-03T11:30:00-08:00" "")
           "2021-03-03T19:30:00+0000"))
  (should (equal
           (convert-time-to-local-timezone "2021-03-03T11:30:00-08:00" "Europe/London")
           "2021-03-03T19:30:00+0000"))
  ;; FIXME: Passed in local with Emacs 26.3 and 27.1, Failed in GitHub CI
  ;; (should (equal
  ;;          (convert-time-to-local-timezone "2021-03-03T11:30:00-08:00" "Europe/Oslo")
  ;;          "2021-03-03T20:30:00+0100"))
  ;; (should (equal
  ;;          (convert-time-to-local-timezone "2021-03-03T11:30:00-08:00" "America/New_York")
  ;;          "2021-03-03T14:30:00-0500"))
  ;; (should (equal
  ;;          (convert-time-to-local-timezone "2021-03-03T11:30:00-08:00" "America/Los_Angeles")
  ;;          "2021-03-03T11:30:00-0800"))
  ;; (should (equal
  ;;          (convert-time-to-local-timezone "2021-03-03T11:30:00-08:00" "Asia/Shanghai")
  ;;          "2021-03-04T03:30:00+0800"))
  )


;;; TODO: Figure out mocking for POST/PATCH followed by GET
;;; - ‘mock‘ might work for this - the argument list must be specified up
;;;   front, but the wildcard ‘*’ can be used to match any value. If that
;;;   doesn’t work, use ‘cl-flet’.

;;; TODO: Figure out how to set up org-id for mocking (org-mode tests should help?)
;;; - There are actually no org-mode tests for this.
;;; - Set ‘org-id-locations’ (a hash table). This maps each ID to the file in
;;;   which the ID is found, so a temp file (not just a temp buffer) is needed.
