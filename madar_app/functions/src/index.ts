import * as admin from "firebase-admin";

import { computeMeetingPointSuggestions } from "./meeting_point_suggester";

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

   Auto-mark Refresh Notifications When Location Updates

   - If user's location.updatedAt is newer than a refresh notification,
     mark it as read + actionTaken (from any source).

-------------------------------------------------------------------*/

export const onUserLocationUpdated = onDocumentUpdated(
  "users/{userId}",
  async (event) => {
    try {
      const before = event.data?.before.data();
      const after = event.data?.after.data();
      if (!after) return;

      const toDate = (v: any) =>
        v && typeof v.toDate === "function" ? v.toDate() : null;

      const beforeUpdatedAt = toDate(before?.location?.updatedAt);
      const afterUpdatedAt = toDate(after?.location?.updatedAt);

      if (!afterUpdatedAt) return;
      if (beforeUpdatedAt && afterUpdatedAt <= beforeUpdatedAt) return;

      const userId = event.params.userId;
      if (!userId) return;

      const snap = await db
        .collection("notifications")
        .where("userId", "==", userId)
        .where("type", "==", "locationRefresh")
        .get();

      if (snap.empty) return;

      let batch = db.batch();
      let ops = 0;
      const commits: Promise<any>[] = [];

      for (const doc of snap.docs) {
        const data: any = doc.data() ?? {};
        const createdAt = toDate(data.createdAt);
        if (!createdAt) continue;
        if (createdAt > afterUpdatedAt) continue;
        if (data.actionTaken === true) continue;

        batch.update(doc.ref, {
          actionTaken: true,
          isRead: true,
          actionTakenAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        ops++;
        if (ops >= 450) {
          commits.push(batch.commit());
          batch = db.batch();
          ops = 0;
        }
      }

      if (ops > 0) commits.push(batch.commit());
      if (commits.length > 0) await Promise.all(commits);
    } catch (error) {
      console.error("Error marking refresh notifications as read:", error);
    }
  }
);
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



      if (tokens.length > 0) {
        const response = await admin.messaging().sendEachForMulticast(message);
        console.log(
          `Notification sent | success: ${response.successCount}, failure: ${response.failureCount}`
        );
      } else {
        console.log("No FCM tokens for receiver (saved to Firestore only)");
      }



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

   Meeting Point Request Notification (Created)

-------------------------------------------------------------------*/

export const onMeetingPointCreated = onDocumentCreated(
  "meetingPoints/{meetingPointId}",
  async (event) => {
    try {
      const data = event.data?.data();
      if (!data) return;

      const meetingPointId = event.params.meetingPointId;
      const hostId = (data.hostId ?? "").toString().trim();
      const hostName =
        (data.hostName ?? "Someone").toString().trim() || "Someone";
      const hostPhone = (data.hostPhone ?? "").toString().trim();
      const venueId = (data.venueId ?? "").toString().trim();
      const venueName = (data.venueName ?? "").toString().trim();
      const waitDeadline = data.waitDeadline ?? null;

      const invitedIds: string[] = Array.isArray(data.invitedUserIds)
        ? data.invitedUserIds.map((v: any) => (v ?? "").toString().trim())
        : [];
      const participantIds: string[] = Array.isArray(data.participants)
        ? data.participants
            .map((p: any) => (p?.userId ?? "").toString().trim())
            .filter((v: string) => v.length > 0)
        : [];

      const targetIds = Array.from(
        new Set([...invitedIds, ...participantIds])
      ).filter((id) => id && id !== hostId);

      if (targetIds.length === 0) {
        console.log("No invited users for meeting point");
        return;
      }

      const title = "Meeting Point Request";
      const body = `${hostName} invites you to a shared meeting point`;

      const batch = db.batch();

      for (const uid of targetIds) {
        const userDoc = await db.collection("users").doc(uid).get();
        if (!userDoc.exists) continue;

        const tokens: string[] = userDoc.data()?.fcmTokens ?? [];

        if (tokens.length > 0) {
          try {
            await admin.messaging().sendEachForMulticast({
              notification: {
                title,
                body,
              },
              data: {
                type: "meetingPointRequest",
                requestId: meetingPointId,
                meetingPointId: meetingPointId,
              },
              tokens,
            });
          } catch (err) {
            console.error(`Failed to send meeting point push to ${uid}`, err);
          }
        } else {
          console.log(`No FCM tokens for user ${uid}`);
        }

        const notifRef = db.collection("notifications").doc();
        batch.set(notifRef, {
          userId: uid,
          type: "meetingPointRequest",
          requiresAction: true,
          actionTaken: false,
          isRead: false,
          requestStatus: "pending",
          title,
          body,
          data: {
            requestId: meetingPointId,
            meetingPointId: meetingPointId,
            senderId: hostId || null,
            senderName: hostName || null,
            senderPhone: hostPhone || null,
            venueId: venueId || null,
            venueName: venueName || null,
            waitDeadline: waitDeadline || null,
            waitDurationSeconds: data.waitDurationSeconds ?? null,
          },
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();
    } catch (error) {
      console.error("Error sending meeting point notifications:", error);
    }
  }
);

/* ------------------------------------------------------------------

   Meeting Point Request Notification (Wait Deadline Set)

   - When waitDeadline becomes available (or changes), push it into the
     pending invite notifications so the countdown appears immediately
     without extra client reads.

-------------------------------------------------------------------*/

export const onMeetingPointWaitDeadlineSet = onDocumentUpdated(
  "meetingPoints/{meetingPointId}",
  async (event) => {
    try {
      const before = event.data?.before.data();
      const after = event.data?.after.data();
      if (!before || !after) return;

      const beforeMs = before.waitDeadline?.toMillis?.() ?? null;
      const afterMs = after.waitDeadline?.toMillis?.() ?? null;
      if (afterMs == null || afterMs === beforeMs) return;

      const meetingPointId = event.params.meetingPointId;
      if (!meetingPointId) return;

      const hostId = (after.hostId ?? "").toString().trim();
      const participants: any[] = Array.isArray(after.participants)
        ? after.participants
        : [];
      const targetIds = participants
        .map((p: any) => (p?.userId ?? "").toString().trim())
        .filter((uid: string) => uid && uid !== hostId);

      if (targetIds.length === 0) return;

      let batch = db.batch();
      let ops = 0;
      const commits: Promise<any>[] = [];

      for (const uid of targetIds) {
        const snap = await db
          .collection("notifications")
          .where("userId", "==", uid)
          .where("type", "==", "meetingPointRequest")
          .get();

        for (const doc of snap.docs) {
          const data: any = doc.data() ?? {};
          const payload: any = data.data ?? {};
          const requestId = (payload.meetingPointId ??
            payload.requestId ??
            "").toString();
          if (requestId !== meetingPointId) continue;

          batch.update(doc.ref, {
            "data.waitDeadline": after.waitDeadline,
          });

          ops++;
          if (ops >= 450) {
            commits.push(batch.commit());
            batch = db.batch();
            ops = 0;
          }
        }
      }

      if (ops > 0) commits.push(batch.commit());
      if (commits.length > 0) await Promise.all(commits);
    } catch (error) {
      console.error("Error updating waitDeadline in notifications:", error);
    }
  }
);

/* ------------------------------------------------------------------

   Meeting Point Request Notification (Status Update)

   - When a participant accepts/declines, update their notification
     to reflect the new status.

-------------------------------------------------------------------*/

export const onMeetingPointParticipantStatusChanged = onDocumentUpdated(
  "meetingPoints/{meetingPointId}",
  async (event) => {
    try {
      const before = event.data?.before.data();
      const after = event.data?.after.data();
      if (!before || !after) return;

      const meetingPointId = event.params.meetingPointId;
      if (!meetingPointId) return;

      const hostId = (after.hostId ?? "").toString().trim();

      const normalizeStatus = (raw: any) => {
        const s = (raw ?? "pending").toString().trim().toLowerCase();
        return s === "accepted" || s === "declined" || s === "pending"
          ? s
          : "pending";
      };

      const buildMap = (list: any[]) => {
        const map = new Map<string, string>();
        for (const p of list) {
          const uid = (p?.userId ?? "").toString().trim();
          if (!uid) continue;
          map.set(uid, normalizeStatus(p?.status));
        }
        return map;
      };

      const beforeParticipants: any[] = Array.isArray(before.participants)
        ? before.participants
        : [];
      const afterParticipants: any[] = Array.isArray(after.participants)
        ? after.participants
        : [];

      const beforeMap = buildMap(beforeParticipants);
      const afterMap = buildMap(afterParticipants);

      const changed: Array<{ uid: string; status: string }> = [];
      for (const [uid, status] of afterMap.entries()) {
        if (!uid || uid === hostId) continue;
        const prev = beforeMap.get(uid) ?? "pending";
        if (status === prev) continue;
        if (status !== "accepted" && status !== "declined") continue;
        changed.push({ uid, status });
      }

      if (changed.length === 0) return;

      let batch = db.batch();
      let ops = 0;
      const commits: Promise<any>[] = [];

      for (const item of changed) {
        const snap = await db
          .collection("notifications")
          .where("userId", "==", item.uid)
          .where("type", "==", "meetingPointRequest")
          .get();

        for (const doc of snap.docs) {
          const data: any = doc.data() ?? {};
          const payload: any = data.data ?? {};
          const requestId = (payload.meetingPointId ??
            payload.requestId ??
            "").toString();
          if (requestId !== meetingPointId) continue;

          batch.update(doc.ref, {
            requestStatus: item.status,
            "data.requestStatus": item.status,
            actionTaken: true,
            requiresAction: false,
            actionTakenAt: admin.firestore.FieldValue.serverTimestamp(),
          });

          ops++;
          if (ops >= 450) {
            commits.push(batch.commit());
            batch = db.batch();
            ops = 0;
          }
        }
      }

      if (ops > 0) commits.push(batch.commit());
      if (commits.length > 0) await Promise.all(commits);
    } catch (error) {
      console.error(
        "Error updating meeting point notification status:",
        error
      );
    }
  }
);

/* ------------------------------------------------------------------

   Meeting Point Request Notification (Cancelled)

   - When the meeting is cancelled, mark PENDING invitees as cancelled
     so their notifications show "Cancelled" and buttons are hidden.

-------------------------------------------------------------------*/

export const onMeetingPointCancelled = onDocumentUpdated(
  "meetingPoints/{meetingPointId}",
  async (event) => {
    try {
      const before = event.data?.before.data();
      const after = event.data?.after.data();
      if (!before || !after) return;

      const normalizeStatus = (raw: any) => {
        const s = (raw ?? "pending").toString().trim().toLowerCase();
        return s === "cancelled" || s === "completed" || s === "active"
          ? s
          : "pending";
      };

      const beforeStatus = normalizeStatus(before.status);
      const afterStatus = normalizeStatus(after.status);

      if (beforeStatus === afterStatus) return;
      if (afterStatus !== "cancelled") return;

      const meetingPointId = event.params.meetingPointId;
      if (!meetingPointId) return;

      const hostId = (after.hostId ?? "").toString().trim();

      const participants: any[] = Array.isArray(after.participants)
        ? after.participants
        : [];

      const pendingIds = participants
        .filter((p: any) => {
          const status = (p?.status ?? "pending").toString().trim().toLowerCase();
          return status === "pending";
        })
        .map((p: any) => (p?.userId ?? "").toString().trim())
        .filter((uid: string) => uid && uid !== hostId);

      if (pendingIds.length === 0) return;

      let batch = db.batch();
      let ops = 0;
      const commits: Promise<any>[] = [];

      for (const uid of pendingIds) {
        const snap = await db
          .collection("notifications")
          .where("userId", "==", uid)
          .where("type", "==", "meetingPointRequest")
          .get();

        for (const doc of snap.docs) {
          const data: any = doc.data() ?? {};
          const payload: any = data.data ?? {};
          const requestId = (payload.meetingPointId ??
            payload.requestId ??
            "").toString();
          if (requestId !== meetingPointId) continue;

          const currentStatus = (data.requestStatus ??
            payload.requestStatus ??
            "pending")
            .toString()
            .trim()
            .toLowerCase();
          if (currentStatus !== "pending") {
            continue;
          }

          batch.update(doc.ref, {
            requestStatus: "cancelled",
            "data.requestStatus": "cancelled",
            actionTaken: true,
            requiresAction: false,
            actionTakenAt: admin.firestore.FieldValue.serverTimestamp(),
          });

          ops++;
          if (ops >= 450) {
            commits.push(batch.commit());
            batch = db.batch();
            ops = 0;
          }
        }
      }

      if (ops > 0) commits.push(batch.commit());
      if (commits.length > 0) await Promise.all(commits);
    } catch (error) {
      console.error("Error updating cancelled meeting notifications:", error);
    }
  }
);

/* ------------------------------------------------------------------

   Meeting Point Request Notification (Expired)

   - When host moves from step 4 → 5, any PENDING invitees should
     be marked as expired (no more accept/decline).

-------------------------------------------------------------------*/

export const onMeetingPointInviteWindowClosed = onDocumentUpdated(
  "meetingPoints/{meetingPointId}",
  async (event) => {
    try {
      const before = event.data?.before.data();
      const after = event.data?.after.data();
      if (!before || !after) return;

      const beforeStep = Number(before.hostStep ?? 0);
      const afterStep = Number(after.hostStep ?? 0);
      if (!(beforeStep === 4 && afterStep === 5)) return;

      const status = (after.status ?? "").toString().trim().toLowerCase();
      if (status && status !== "pending") return;

      const meetingPointId = event.params.meetingPointId;
      if (!meetingPointId) return;

      const hostId = (after.hostId ?? "").toString().trim();

      const participants: any[] = Array.isArray(after.participants)
        ? after.participants
        : [];

      const pendingIds = participants
        .filter((p: any) => {
          const s = (p?.status ?? "pending").toString().trim().toLowerCase();
          return s === "pending";
        })
        .map((p: any) => (p?.userId ?? "").toString().trim())
        .filter((uid: string) => uid && uid !== hostId);

      if (pendingIds.length === 0) return;

      let batch = db.batch();
      let ops = 0;
      const commits: Promise<any>[] = [];

      for (const uid of pendingIds) {
        const snap = await db
          .collection("notifications")
          .where("userId", "==", uid)
          .where("type", "==", "meetingPointRequest")
          .get();

        for (const doc of snap.docs) {
          const data: any = doc.data() ?? {};
          const payload: any = data.data ?? {};
          const requestId = (payload.meetingPointId ??
            payload.requestId ??
            "").toString();
          if (requestId !== meetingPointId) continue;

          batch.update(doc.ref, {
            requestStatus: "expired",
            "data.requestStatus": "expired",
            actionTaken: true,
            requiresAction: false,
            actionTakenAt: admin.firestore.FieldValue.serverTimestamp(),
          });

          ops++;
          if (ops >= 450) {
            commits.push(batch.commit());
            batch = db.batch();
            ops = 0;
          }
        }
      }

      if (ops > 0) commits.push(batch.commit());
      if (commits.length > 0) await Promise.all(commits);
    } catch (error) {
      console.error("Error marking meeting invites as expired:", error);
    }
  }
);

/* ------------------------------------------------------------------

   Meeting Point Suggestions (Computed)

   - When hostStep becomes 5 (manual or auto), compute suggested meeting
     point candidates using entrances + navmesh + connectors.

-------------------------------------------------------------------*/

export const onMeetingPointSuggest = onDocumentUpdated(
  "meetingPoints/{meetingPointId}",
  async (event) => {
    try {
      const after = event.data?.after.data();
      if (!after) return;

      const meetingPointId = event.params.meetingPointId;
      if (!meetingPointId) return;

      const afterStep = Number(after.hostStep ?? 0);

      const status = (after.status ?? "").toString().trim().toLowerCase();
      if (status && status !== "pending") return;

      const alreadySuggested =
        (after.suggestedPoint ?? "").toString().trim().length > 0;
      if (alreadySuggested || after.suggestionsComputed === true) return;

      const participants: any[] = Array.isArray(after.participants)
        ? after.participants
        : [];
      const anyAccepted = participants.some(
        (p: any) =>
          (p?.status ?? "").toString().trim().toLowerCase() === "accepted"
      );
      if (!anyAccepted) return;

      const allResponded = participants.every(
        (p: any) =>
          (p?.status ?? "").toString().trim().toLowerCase() !== "pending"
      );
      const toDate = (v: any) =>
        v && typeof v.toDate === "function" ? v.toDate() : null;
      const waitDeadline = toDate(after.waitDeadline);
      const waitExpired = waitDeadline
        ? waitDeadline.getTime() <= Date.now()
        : false;

      // Compute suggestions when host is on step 5 OR everyone responded OR
      // the wait timer expired (auto-advance safety net).
      if (!(afterStep === 5 || allResponded || waitExpired)) return;

      const result = await computeMeetingPointSuggestions(
        meetingPointId,
        after
      );

      if (!result) {
        await db.collection("meetingPoints").doc(meetingPointId).update({
          suggestionsComputed: true,
          suggestionError: "no_candidates",
          suggestedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return;
      }

      await db.collection("meetingPoints").doc(meetingPointId).update({
        suggestedPoint: result.suggestedPoint,
        suggestedCandidates: result.suggestedCandidates,
        suggestionsComputed: true,
        suggestedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (error) {
      console.error("Error computing meeting point suggestions:", error);
    }
  }
);

/* ------------------------------------------------------------------

   Auto Refresh Location (Scheduled)

   - If tracking is active and receiver hasn't updated location for 1 hour,
     send "Refresh Your Location" notification from system.

-------------------------------------------------------------------*/

export const onAutoLocationRefresh = onSchedule(
  "every 5 minutes",
  async () => {
    try {
      const now = admin.firestore.Timestamp.now();

      const snap = await db
        .collection("trackRequests")
        .where("status", "==", "accepted")
        .where("startAt", "<=", now)
        .get();

      if (snap.empty) return;

      const userCache = new Map<
        string,
        { tokens: string[]; updatedAt: admin.firestore.Timestamp | null }
      >();

      const getUserInfo = async (uid: string) => {
        if (userCache.has(uid)) return userCache.get(uid)!;
        const userDoc = await db.collection("users").doc(uid).get();
        if (!userDoc.exists) {
          const info = { tokens: [] as string[], updatedAt: null };
          userCache.set(uid, info);
          return info;
        }
        const data = userDoc.data() ?? {};
        const tokens: string[] = data.fcmTokens ?? [];
        const updatedAt: admin.firestore.Timestamp | null =
          data.location?.updatedAt ?? null;
        const info = { tokens, updatedAt };
        userCache.set(uid, info);
        return info;
      };

      const cutoff = new Date(now.toDate().getTime() - 60 * 60 * 1000);
      const batch = db.batch();

      for (const doc of snap.docs) {
        const data = doc.data();
        const endAt = data.endAt;
        const endAtDate =
          endAt && typeof endAt.toDate === "function" ? endAt.toDate() : null;
        if (!endAtDate || endAtDate <= now.toDate()) continue;

        const receiverId = (data.receiverId ?? "").toString().trim();
        if (!receiverId) continue;

        const userInfo = await getUserInfo(receiverId);
        const lastUpdate =
          userInfo.updatedAt &&
          typeof userInfo.updatedAt.toDate === "function"
            ? userInfo.updatedAt.toDate()
            : null;

        const lastAuto =
          data.lastAutoRefreshAt &&
          typeof data.lastAutoRefreshAt.toDate === "function"
            ? data.lastAutoRefreshAt.toDate()
            : null;

        const isStale = !lastUpdate || lastUpdate <= cutoff;
        const cooldownPassed = !lastAuto || lastAuto <= cutoff;

        // Send every hour while stale
        if (!isStale || !cooldownPassed) continue;

        const title = "Refresh Location Request";
        const body = "You are in an active session, Please refresh your location for better accuracy";

        // Replace previous pending system refresh notification (same session)
        const lastNotifId = (data.lastAutoRefreshNotifId ?? "").toString();
        let notifRef = lastNotifId
          ? db.collection("notifications").doc(lastNotifId)
          : db.collection("notifications").doc();
        let reuseExisting = false;

        if (lastNotifId) {
          const lastSnap = await notifRef.get();
          if (lastSnap.exists) {
            const lastData: any = lastSnap.data() ?? {};
            const lastPayload: any = lastData.data ?? {};
            const matchesSession =
              lastData.userId === receiverId &&
              lastData.type === "locationRefresh" &&
              lastPayload.trackRequestId === doc.id &&
              lastPayload.system === true;
            const pending = lastData.actionTaken !== true;
            if (matchesSession && pending) reuseExisting = true;
          }
        }

        if (!reuseExisting) {
          notifRef = db.collection("notifications").doc();
        }
        const notifId = notifRef.id;

        if (userInfo.tokens.length > 0) {
          await admin.messaging().sendEachForMulticast({
            notification: {
              title,
              body,
            },
            data: {
              type: "locationRefresh",
              requestId: notifId,
              trackRequestId: doc.id,
            },
            tokens: userInfo.tokens,
          });
        }

        batch.set(notifRef, {
          userId: receiverId,
          type: "locationRefresh",
          requiresAction: true,
          actionTaken: false,
          isRead: false,
          title,
          body,
          data: {
            requestId: notifId,
            trackRequestId: doc.id,
            senderId: data.senderId ?? null,
            senderName: data.senderName ?? null,
            senderPhone: data.senderPhone ?? null,
            venueId: data.venueId ?? null,
            venueName: data.venueName ?? null,
            endAt: data.endAt ?? null,
            system: true,
          },
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        batch.update(doc.ref, {
          lastAutoRefreshAt: admin.firestore.FieldValue.serverTimestamp(),
          lastAutoRefreshNotifId: notifId,
        });
      }

      await batch.commit();
    } catch (error) {
      console.error("Error sending auto refresh notification:", error);
    }
  }
);

/* ------------------------------------------------------------------

   Purge Old Notifications (Scheduled)

   - Deletes notifications older than 30 days.

-------------------------------------------------------------------*/

export const purgeOldNotifications = onSchedule("every 24 hours", async () => {
  try {
    const cutoff = admin.firestore.Timestamp.fromDate(
      new Date(Date.now() - 30 * 24 * 60 * 60 * 1000)
    );

    let totalDeleted = 0;

    while (true) {
      const snap = await db
        .collection("notifications")
        .where("createdAt", "<", cutoff)
        .limit(450)
        .get();

      if (snap.empty) break;

      const batch = db.batch();
      for (const doc of snap.docs) {
        batch.delete(doc.ref);
      }

      await batch.commit();
      totalDeleted += snap.size;

      if (snap.size < 450) break;
    }

    console.log(`purgeOldNotifications deleted ${totalDeleted} docs`);
  } catch (error) {
    console.error("Error purging old notifications:", error);
  }
});



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



      // Only handle accepted/declined/terminated/cancelled

      if (
        after.status !== "accepted" &&
        after.status !== "declined" &&
        after.status !== "terminated" &&
        after.status !== "cancelled"
      )
        return;

      // Cancelled: notify receiver only if it was previously accepted
      if (after.status === "cancelled") {
        if (before.status !== "accepted") return;

        const receiverId = after.receiverId;
        if (!receiverId) return;

        const receiverDoc = await db.collection("users").doc(receiverId).get();
        if (!receiverDoc.exists) return;

        const receiverTokens: string[] = receiverDoc.data()?.fcmTokens ?? [];

        const senderName =
          (after.senderName ?? "Someone").toString().trim() || "Someone";

        const notifRef = db.collection("notifications").doc();
        const notifId = notifRef.id;

        if (receiverTokens.length > 0) {
          await admin.messaging().sendEachForMulticast({
            notification: {
              title: "Tracking Request Cancelled",
              body: `${senderName} cancelled the tracking request`,
            },
            data: {
              type: "trackCancelled",
              requestId: notifId,
              trackRequestId: event.params.requestId,
            },
            tokens: receiverTokens,
          });
        }

        await notifRef.set({
          userId: receiverId,
          type: "trackCancelled",
          requiresAction: false,
          data: {
            requestId: notifId,
            trackRequestId: event.params.requestId,
          },
          title: "Tracking Request Cancelled",
          body: `${senderName} cancelled the tracking request`,
          isRead: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        return;
      }



      const senderId = after.senderId;

      if (!senderId) return;



      const senderDoc = await db.collection("users").doc(senderId).get();

      if (!senderDoc.exists) return;



      const tokens: string[] = senderDoc.data()?.fcmTokens ?? [];



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



      if (tokens.length > 0) {
        await admin.messaging().sendEachForMulticast(message);
      }



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

   Refresh Location Request (Active Tracking)

-------------------------------------------------------------------*/

export const onTrackRefreshRequested = onDocumentUpdated(

  "trackRequests/{requestId}",

  async (event) => {

    try {

      const before = event.data?.before.data();

      const after = event.data?.after.data();

      if (!before || !after) return;



      const beforeToken = (before.refreshRequestId ?? "").toString();

      const afterToken = (after.refreshRequestId ?? "").toString();



      // Only handle new refresh request tokens

      if (!afterToken || afterToken === beforeToken) return;



      // Only allow during active accepted tracking

      if (after.status !== "accepted") return;



      const toDate = (v: any) =>

        v && typeof v.toDate === "function" ? v.toDate() : null;

      const startAt = toDate(after.startAt);

      const endAt = toDate(after.endAt);

      if (!startAt || !endAt) return;



      const now = new Date();

      if (now < startAt || now > endAt) return;



      const senderId = (after.senderId ?? "").toString();

      const receiverId = (after.receiverId ?? "").toString();

      if (!senderId || !receiverId) return;



      const requestedBy = (after.refreshRequestedBy ?? "").toString();

      if (requestedBy && requestedBy !== senderId) return;



      const senderName =

        (after.senderName ?? "Someone").toString().trim() || "Someone";



      const title = "Refresh Location Request";

      const body = `${senderName} asked to refresh your location`;



      const receiverDoc = await db.collection("users").doc(receiverId).get();

      if (!receiverDoc.exists) return;



      const tokens: string[] = receiverDoc.data()?.fcmTokens ?? [];



      // Replace previous pending refresh notification (same sender + session)
      const lastNotifId = (after.lastRefreshNotifId ?? "").toString();
      let notifRef = lastNotifId
        ? db.collection("notifications").doc(lastNotifId)
        : db.collection("notifications").doc();
      let reuseExisting = false;

      if (lastNotifId) {
        const lastSnap = await notifRef.get();
        if (lastSnap.exists) {
          const lastData: any = lastSnap.data() ?? {};
          const lastPayload: any = lastData.data ?? {};
          const matchesSession =
            lastData.userId === receiverId &&
            lastData.type === "locationRefresh" &&
            lastPayload.trackRequestId === event.params.requestId &&
            lastPayload.senderId === senderId &&
            lastPayload.system !== true;
          const pending = lastData.actionTaken !== true;
          if (matchesSession && pending) reuseExisting = true;
        }
      }

      if (!reuseExisting) {
        notifRef = db.collection("notifications").doc();
      }

      const notifId = notifRef.id;



      if (tokens.length > 0) {

        await admin.messaging().sendEachForMulticast({

          notification: {

            title,

            body,

          },

          data: {

            type: "locationRefresh",

            requestId: notifId,

            trackRequestId: event.params.requestId,

          },

          tokens,

        });

      }



      await notifRef.set({

        userId: receiverId,

        type: "locationRefresh",

        requiresAction: true,

        actionTaken: false,

        isRead: false,

        title,

        body,

        data: {

          requestId: notifId,

          trackRequestId: event.params.requestId,

          senderId,

          senderName,

          senderPhone: after.senderPhone ?? null,

          venueId: after.venueId ?? null,

          venueName: after.venueName ?? null,

          endAt: after.endAt ?? null,

          refreshRequestId: afterToken,
          system: false,

        },

        createdAt: admin.firestore.FieldValue.serverTimestamp(),

      });



      await event.data!.after.ref.update({
        lastRefreshNotifId: notifId,
      });



      console.log("Refresh location notification sent");

    } catch (error) {

      console.error("Error sending refresh location notification:", error);

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
            body: `${data.senderName} can now track your location, please set your location`,
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
        body: `${data.senderName} can now track your location, please set your location`,
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

   Track Completed Notification (Scheduled)

-------------------------------------------------------------------*/

export const onTrackCompleted = onSchedule("every 1 minutes", async () => {
  const now = admin.firestore.Timestamp.now();

  const snap = await db
    .collection("trackRequests")
    .where("status", "==", "accepted")
    .where("endAt", "<=", now)
    .get();

  if (snap.empty) return;

  const batch = db.batch();
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

  for (const doc of snap.docs) {
    const data = doc.data();
    if (data.completedNotified === true) continue;

    const receiverId = data.receiverId;
    if (!receiverId) continue;

    const senderName =
      (data.senderName ?? "Someone").toString().trim() || "Someone";

    const receiverTokens = await getTokens(receiverId);
    const notifRef = db.collection("notifications").doc();
    const notifId = notifRef.id;

    if (receiverTokens.length > 0) {
      await admin.messaging().sendEachForMulticast({
        notification: {
          title: "Tracking Completed",
          body: `Tracking session from ${senderName} has ended`,
        },
        data: {
          type: "trackCompleted",
          requestId: notifId,
          trackRequestId: doc.id,
        },
        tokens: receiverTokens,
      });
    }

    batch.set(notifRef, {
      userId: receiverId,
      type: "trackCompleted",
      requiresAction: false,
      isRead: false,
      title: "Tracking Completed",
      body: `Tracking session from ${senderName} has ended`,
      data: {
        requestId: notifId,
        trackRequestId: doc.id,
        senderId: data.senderId ?? null,
      },
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    batch.update(doc.ref, {
      status: "completed",
      completedNotified: true,
      completedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
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




