Google's Firebase web library, version 13.4.0, served from this site so the
match page loads nothing from another server:

  firebase-app.js        https://www.gstatic.com/firebasejs/13.4.0/firebase-app.js
  firebase-firestore.js  https://www.gstatic.com/firebasejs/13.4.0/firebase-firestore.js

firebase-firestore.js is unchanged except for one line: it imports
"./firebase-app.js" where the original names the gstatic address.

Licence: Apache License 2.0, https://github.com/firebase/firebase-js-sdk/blob/main/LICENSE

To update: download both files for the new version, make the same one-line
change, and run `node --test site_tests`.
