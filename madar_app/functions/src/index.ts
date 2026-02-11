import * as admin from "firebase-admin";

import { setGlobalOptions } from "firebase-functions";

import { onDocumentCreated, onDocumentUpdated } from "firebase-functions/v2/firestore";

import { onRequest } from "firebase-functions/v2/https";

import { onSchedule } from "firebase-functions/v2/scheduler";

//import { Timestamp } from "firebase-admin/firestore";



setGlobalOptions({ maxInstances: 10 });



// Initialize Firebase Admin

admin.initializeApp();

const db = admin.firestore();



/* ------------------------------------------------------------------

   Track Request Push Notification (Created)

-------------------------------------------------------------------*/

export const onTrackRequestCreated = onDocumentCreated(

  "trackRequests/{requestId}",

  async (event) => {

    try {

      const data = event.data?.data();

      if (!data) {

        console.log("No data in track request");

        return;

      }



      // Send notification only when created as pending

      if (data.status !== "pending") {

        console.log("Track request not pending, skipping");

        return;

      }



      const receiverId = data.receiverId;

      if (!receiverId) {

        console.log("No receiverId");

        return;

      }



      // Get receiver FCM tokens

      const userDoc = await db.collection("users").doc(receiverId).get();

      if (!userDoc.exists) {

        console.log("Receiver user not found");

        return;

      }



      const tokens: string[] = userDoc.data()?.fcmTokens ?? [];

      if (tokens.length === 0) {

        console.log("No FCM tokens for receiver");

        return;

      }



      const message = {

        notification: {

          title: "New Track Request",

          body: `${data.senderName} wants to track your location`,

        },

        data: {

          type: "trackRequest",

          requestId: event.params.requestId,

        },

        tokens,

      };



      const response = await admin.messaging().sendEachForMulticast(message);



      console.log(

        `Notification sent | success: ${response.successCount}, failure: ${response.failureCount}`

      );



      // Save notification in Firestore (Unread)

      await db.collection("notifications").add({

        userId: receiverId,

        type: "track_request",

        requiresAction: true, // IMPORTANT: UI can show action buttons

        title: "New Track Request",

        body: `${data.senderName} wants to track your location`,

        data: {

          requestId: event.params.requestId,

          senderId: data.senderId,

          venueId: data.venueId ?? null,

        },

        isRead: false,

        createdAt: admin.firestore.FieldValue.serverTimestamp(),

      });



      console.log("Notification document created (unread)");

    } catch (error) {

      console.error("Error sending track request notification:", error);

    }

  }

);



/* ------------------------------------------------------------------

   Track Request Push Notification (Accepted / Declined)

-------------------------------------------------------------------*/

export const onTrackRequestStatusChanged = onDocumentUpdated(

  "trackRequests/{requestId}",

  async (event) => {

    try {

      const before = event.data?.before.data();

      const after = event.data?.after.data();

      if (!before || !after) return;



      // Do nothing if status did not change

      if (before.status === after.status) return;



      // Only handle accepted/declined/terminated

      if (
        after.status !== "accepted" &&
        after.status !== "declined" &&
        after.status !== "terminated"
      )
        return;



      const senderId = after.senderId;

      if (!senderId) return;



      const senderDoc = await db.collection("users").doc(senderId).get();

      if (!senderDoc.exists) return;



      const tokens: string[] = senderDoc.data()?.fcmTokens ?? [];

      if (tokens.length === 0) return;



      const status = after.status;
      const accepted = status === "accepted";
      const terminated = status === "terminated";
      const receiverName =
        (after.receiverName ?? "Someone").toString().trim() || "Someone";

      const notifRef = terminated
        ? db.collection("notifications").doc()
        : null;
      const notificationRequestId = terminated
        ? notifRef!.id
        : event.params.requestId;

      const message = {
        notification: {
          title: terminated
            ? "Tracking Request Terminated"
            : accepted
              ? "Tracking Request Accepted"
              : "Tracking Request Declined",
          body: terminated
            ? `${receiverName} stopped sharing the location with you`
            : accepted
              ? `${receiverName} accepted your tracking request`
              : `${receiverName} declined your tracking request`,
        },
        data: {
          type: terminated
            ? "trackTerminated"
            : accepted
              ? "trackAccepted"
              : "trackDeclined",
          requestId: notificationRequestId,
        },
        tokens,
      };



      await admin.messaging().sendEachForMulticast(message);



      if (terminated) {
        await notifRef!.set({
          userId: senderId,
          type: "trackTerminated",
          requiresAction: false,
          data: {
            requestId: notificationRequestId,
            trackRequestId: event.params.requestId,
          },
          title: "Tracking Request Terminated",
          body: `${receiverName} stopped sharing the location with you`,
          isRead: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      } else {
        await db.collection("notifications").add({
          userId: senderId,
          type: accepted ? "trackAccepted" : "trackRejected",
          requiresAction: false,
          data: {
            requestId: event.params.requestId,
          },
          title: accepted ? "Track Request Accepted" : "Track Request Declined",
          body: accepted
            ? `${receiverName} accepted your tracking request`
            : `${receiverName} declined your tracking request`,
          isRead: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }



      console.log("Accept/Decline notification sent");

    } catch (e) {

      console.error("Error:", e);

    }

  }

);

/* ------------------------------------------------------------------

   🔔 Track Started Notification (Scheduled)

-------------------------------------------------------------------*/

export const onTrackStarted = onSchedule("every 1 minutes", async () => {
  const now = admin.firestore.Timestamp.now();

  const snap = await db
    .collection("trackRequests")
    .where("status", "==", "accepted")
    .where("startAt", "<=", now)
    .get();

  if (snap.empty) return;

  const batch = db.batch();
  const senderGroups = new Map<
    string,
    {
      senderId: string;
      batchId: string;
      receiverNames: string[];
      docRefs: any[];
      endAt?: admin.firestore.Timestamp;
    }
  >();

  const tokenCache = new Map<string, string[]>();

  const getTokens = async (uid: string) => {
    if (tokenCache.has(uid)) return tokenCache.get(uid)!;
    const userDoc = await db.collection("users").doc(uid).get();
    if (!userDoc.exists) {
      tokenCache.set(uid, []);
      return [];
    }
    const tokens: string[] = userDoc.data()?.fcmTokens ?? [];
    tokenCache.set(uid, tokens);
    return tokens;
  };

  const formatSenderBody = (names: string[]) => {
    const unique = Array.from(
      new Set(
        names
          .map((n) => (n ?? "").toString().trim())
          .filter((n) => n.length > 0)
      )
    );
    if (unique.length === 0) return "You can now track your friends";
    if (unique.length === 1) return `You can now track ${unique[0]}`;
    if (unique.length === 2)
      return `You can now track ${unique[0]} and ${unique[1]}`;
    return `You can now track ${unique[0]} and ${unique.length - 1} others`;
  };

  for (const doc of snap.docs) {
    const data = doc.data();
    const requestId = doc.id;

    const senderId = data.senderId;
    const receiverId = data.receiverId;

    if (!senderId || !receiverId) continue;

    const notifiedUsers: string[] = data.startNotifiedUsers || [];
    const receiverAlreadyNotified = notifiedUsers.includes(receiverId);
    const senderAlreadyNotified =
      data.startNotifiedSender === true || data.startNotified === true;
    const batchId: string = data.batchId || requestId;

    if (!receiverAlreadyNotified) {
      const receiverTokens = await getTokens(receiverId);
      const receiverNotifRef = db.collection("notifications").doc();
      const receiverNotifId = receiverNotifRef.id;

      if (receiverTokens.length > 0) {
        await admin.messaging().sendEachForMulticast({
          notification: {
            title: "Tracking Started",
            body: `${data.senderName} can now track your location`,
          },
          data: {
            type: "trackStarted",
            requestId: receiverNotifId,
            trackRequestId: requestId,
          },
          tokens: receiverTokens,
        });
      }

      batch.set(receiverNotifRef, {
        userId: receiverId,
        type: "trackStarted",
        requiresAction: true,
        isRead: false,
        title: "Tracking Started",
        body: `${data.senderName} can now track your location`,
        data: {
          requestId: receiverNotifId,
          trackRequestId: requestId,
          endAt: data.endAt,
        },
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      batch.update(doc.ref, {
        startNotifiedUsers: admin.firestore.FieldValue.arrayUnion(receiverId),
      });
    }

    let group = senderGroups.get(batchId);
    if (!group) {
      group = {
        senderId,
        batchId,
        receiverNames: [],
        docRefs: [],
        endAt: data.endAt,
      };
      senderGroups.set(batchId, group);
    }

    if (!senderAlreadyNotified) {
      const receiverName = (data.receiverName ?? "").toString().trim();
      const receiverFallback = (data.receiverPhone ?? "").toString().trim();
      if (receiverName) group.receiverNames.push(receiverName);
      else if (receiverFallback) group.receiverNames.push(receiverFallback);
      group.docRefs.push(doc.ref);
    }
  }

  for (const group of senderGroups.values()) {
    if (group.docRefs.length === 0) continue;

    const senderTokens = await getTokens(group.senderId);
    const body = formatSenderBody(group.receiverNames);
    const senderNotifRef = db.collection("notifications").doc();
    const senderNotifId = senderNotifRef.id;

    if (senderTokens.length > 0) {
      await admin.messaging().sendEachForMulticast({
        notification: {
          title: "Tracking Started",
          body,
        },
        data: {
          type: "trackStarted",
          requestId: senderNotifId,
          batchId: group.batchId,
        },
        tokens: senderTokens,
      });
    }

    batch.set(senderNotifRef, {
      userId: group.senderId,
      type: "trackStarted",
      requiresAction: false,
      isRead: false,
      title: "Tracking Started",
      body,
      data: {
        requestId: senderNotifId,
        batchId: group.batchId,
        endAt: group.endAt ?? null,
        receiverNames: group.receiverNames,
      },
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    for (const ref of group.docRefs) {
      batch.update(ref, {
        startNotifiedSender: true,
      });
    }
  }

  await batch.commit();
});

/* ------------------------------------------------------------------

   Unity Location Writer (HTTPS)

   Unity -> POST -> Cloud Function -> writes to users/{docId}.location

-------------------------------------------------------------------*/

export const setUserLocation = onRequest({ cors: true }, async (req, res) => {

  try {

    if (req.method !== "POST") {

      res.status(405).send("Use POST");

      return;

    }



    const { idToken, userDocId, location } = req.body ?? {};



    if (!idToken) {

      res.status(401).json({ ok: false, error: "Missing idToken" });

      return;

    }



    if (!location?.blenderPosition) {

      res.status(400).json({ ok: false, error: "Missing location.blenderPosition" });

      return;

    }



    // Verify Firebase Auth ID token

    const decoded = await admin.auth().verifyIdToken(idToken);



    // Decide which users doc to write

    let docRef: FirebaseFirestore.DocumentReference | null = null;



    if (typeof userDocId === "string" && userDocId.trim().length > 0) {

      docRef = db.collection("users").doc(userDocId.trim());

    } else if (decoded.email) {

      // Fallback: resolve by email (same logic as Flutter)

      const snap = await db

        .collection("users")

        .where("email", "==", decoded.email)

        .limit(1)

        .get();

      if (!snap.empty) docRef = snap.docs[0].ref;

    }



    // Last fallback: uid doc

    if (!docRef) docRef = db.collection("users").doc(decoded.uid);



    // Write location in the exact shape your Flutter reads

    await docRef.set(

      {

        location: {

          blenderPosition: {

            x: location.blenderPosition.x,

            y: location.blenderPosition.y,

            z: location.blenderPosition.z,

            floor: location.blenderPosition.floor ?? "",

          },

          multisetPosition: location.multisetPosition ?? null,

          nearestPOI: location.nearestPOI ?? "Unknown",

          updatedAt: admin.firestore.FieldValue.serverTimestamp(),

        },

      },

      { merge: true }

    );



    res.json({ ok: true, userUid: decoded.uid });

  } catch (e: any) {

    console.error("setUserLocation error:", e);

    res.status(500).json({ ok: false, error: String(e?.message ?? e) });

  }

});

