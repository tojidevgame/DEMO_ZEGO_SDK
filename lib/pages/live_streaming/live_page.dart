import 'dart:async';
import 'dart:convert' as convert;
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../components/common/zego_apply_cohost_list_page.dart';
import '../../components/common/zego_audio_video_view.dart';
import '../../components/common/zego_member_button.dart';
import '../../components/live_streaming/zego_live_bottom_bar.dart';
import '../../components/live_streaming/zego_pk_view.dart';
import '../../internal/sdk/zim/Define/zim_define.dart';
import '../../internal/sdk/utils/flutter_extension.dart';
import '../../internal/sdk/zim/Define/zim_room_request.dart';
import '../../utils/zegocloud_token.dart';
import '../../zego_live_streaming_manager.dart';
import '../../zego_sdk_key_center.dart';
import '../../zego_sdk_manager.dart';
import 'live_page_pk.dart';

const double kButtonSize = 30;

class ZegoLivePage extends StatefulWidget {
  const ZegoLivePage({super.key, required this.roomID, required this.role});

  final String roomID;
  final ZegoLiveRole role;

  @override
  State<ZegoLivePage> createState() => ZegoLivePageState();
}

class ZegoLivePageState extends State<ZegoLivePage> {
  List<StreamSubscription> subscriptions = [];

  ValueNotifier<bool> applying = ValueNotifier(false);

  bool showingDialog = false;
  bool showingPKDialog = false;

  final liveStreamingManager = ZegoLiveStreamingManager();

  @override
  void initState() {
    super.initState();

    liveStreamingManager.init();

    final zimService = ZEGOSDKManager().zimService;
    final expressService = ZEGOSDKManager().expressService;
    subscriptions.addAll([
      expressService.roomStateChangedStreamCtrl.stream.listen(onExpressRoomStateChanged),
      liveStreamingManager.incomingPKRequestStreamCtrl.stream.listen(onIncomingPKRequestReceived),
      liveStreamingManager.incomingPKRequestCancelStreamCtrl.stream.listen(onIncomingPKRequestCancelled),
      liveStreamingManager.outgoingPKRequestAcceptStreamCtrl.stream.listen(onOutgoingPKRequestAccepted),
      liveStreamingManager.outgoingPKRequestRejectedStreamCtrl.stream.listen(onOutgoingPKRequestRejected),
      liveStreamingManager.incomingPKRequestTimeoutStreamCtrl.stream.listen(onIncomingPKRequestTimeout),
      liveStreamingManager.outgoingPKRequestAnsweredTimeoutStreamCtrl.stream.listen(onOutgoingPKRequestTimeout),
      liveStreamingManager.onPKStartStreamCtrl.stream.listen(onPKStart),
      liveStreamingManager.onPKEndStreamCtrl.stream.listen(onPKEnd),
      zimService.roomStateChangedStreamCtrl.stream.listen(onZIMRoomStateChanged),
      zimService.connectionStateStreamCtrl.stream.listen(onZIMConnectionStateChanged),
      zimService.onInComingRoomRequestStreamCtrl.stream.listen(onInComingRoomRequest),
      zimService.onInComingRoomRequestCancelledStreamCtrl.stream.listen(onInComingRoomRequestCancel),
      zimService.onOutgoingRoomRequestAcceptedStreamCtrl.stream.listen(onOutgoingRoomRequestAccepted),
      zimService.onOutgoingRoomRequestRejectedStreamCtrl.stream.listen(onOutgoingRoomRequestRejected),
    ]);

    if (widget.role == ZegoLiveRole.audience) {
      //Join room
      liveStreamingManager.currentUserRoleNoti.value = ZegoLiveRole.audience;

      String? token;
      if (kIsWeb) {
        // ! ** Warning: ZegoTokenUtils is only for use during testing. When your application goes live,
        // ! ** tokens must be generated by the server side. Please do not generate tokens on the client side!
        token = ZegoTokenUtils.generateToken(
            SDKKeyCenter.appID, SDKKeyCenter.serverSecret, ZEGOSDKManager.instance.currentUser!.userID);
      }
      ZEGOSDKManager.instance.loginRoom(widget.roomID, ZegoScenario.Broadcast,token: token).then(
        (value) {
          if (value.errorCode != 0) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text('login room failed: ${value.errorCode}')));
          }
        },
      );
    } else if (widget.role == ZegoLiveRole.host) {
      liveStreamingManager.hostNoti.value = ZEGOSDKManager.instance.currentUser;
      ZegoLiveStreamingManager().currentUserRoleNoti.value = ZegoLiveRole.host;
      ZEGOSDKManager.instance.expressService.turnCameraOn(true);
      ZEGOSDKManager.instance.expressService.turnMicrophoneOn(true);
      ZEGOSDKManager.instance.expressService.startPreview();
    }
  }

  @override
  void dispose() {
    super.dispose();
    liveStreamingManager
      ..leaveRoom()
      ..uninit();
    ZEGOSDKManager.instance.expressService.stopPreview();
    for (final subscription in subscriptions) {
      subscription.cancel();
    }
  }

  @override
  Widget build(Object context) {
    return ValueListenableBuilder<bool>(
      valueListenable: liveStreamingManager.isLivingNotifier,
      builder: (context, isLiveing, _) {
        return ValueListenableBuilder<RoomPKState>(
          valueListenable: ZegoLiveStreamingManager().roomPKStateNoti,
          builder: (context, RoomPKState roomPKState, child) {
            return Scaffold(
              body: Stack(
                children: [
                  backgroundImage(),
                  hostVideoView(),
                  if (roomPKState != RoomPKState.isStartPK) coHostVideoView(),
                  if (!isLiveing && widget.role == ZegoLiveRole.host) startLiveButton(),
                  hostText(),
                  leaveButton(),
                  if (widget.role == ZegoLiveRole.host) memberButton(),
                  if (isLiveing && widget.role == ZegoLiveRole.host) pkButton(),
                  if (isLiveing) bottomBar(),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget bottomBar() {
    return ValueListenableBuilder(
        valueListenable: ZegoLiveStreamingManager().roomPKStateNoti,
        builder: (context, RoomPKState pkState, _) {
          if (pkState == RoomPKState.isNoPK || ZegoLiveStreamingManager().isLocalUserHost()) {
            return LayoutBuilder(
              builder: (context, containers) {
                return Padding(
                  padding: EdgeInsets.only(left: 0, right: 0, top: containers.maxHeight - 70),
                  child: ZegoLiveBottomBar(applying: applying),
                );
              },
            );
          } else {
            return const SizedBox.shrink();
          }
        });
  }

  Widget backgroundImage() {
    return Image.asset(
      'assets/icons/bg.png',
      width: double.infinity,
      height: double.infinity,
      fit: BoxFit.fill,
    );
  }

  Widget hostVideoView() {
    return ValueListenableBuilder(
        valueListenable: liveStreamingManager.roomPKStateNoti,
        builder: (context, RoomPKState pkState, _) {
          return ValueListenableBuilder(
              valueListenable: liveStreamingManager.onPKViewAvaliableNoti,
              builder: (context, bool showPKView, _) {
                if (pkState == RoomPKState.isStartPK) {
                  if (showPKView || liveStreamingManager.isLocalUserHost()) {
                    return LayoutBuilder(builder: (context, constraints) {
                      return Stack(
                        children: [
                          Positioned(
                              top: 100,
                              child: SizedBox(
                                width: constraints.maxWidth,
                                height: constraints.maxWidth * 480 / 540,
                                child: const ZegoPKBattleView(),
                              )),
                        ],
                      );
                    });
                  } else {
                    if (liveStreamingManager.hostNoti.value == null) {
                      return Container();
                    }
                    return ZegoAudioVideoView(userInfo: liveStreamingManager.hostNoti.value!);
                  }
                } else {
                  if (liveStreamingManager.hostNoti.value == null) {
                    return Container();
                  }
                  return ZegoAudioVideoView(userInfo: liveStreamingManager.hostNoti.value!);
                }
              });
        });
  }

  ZegoSDKUser? getHostUser() {
    if (widget.role == ZegoLiveRole.host) {
      return ZEGOSDKManager.instance.currentUser;
    } else {
      for (final userInfo in ZEGOSDKManager.instance.expressService.userInfoList) {
        if (userInfo.streamID != null) {
          if (userInfo.streamID!.endsWith('_host')) {
            return userInfo;
          }
        }
      }
    }
    return null;
  }

  Widget coHostVideoView() {
    return Positioned(
      right: 20,
      top: 100,
      child: Builder(builder: (context) {
        final height = (MediaQuery.of(context).size.height - kButtonSize - 100) / 4;
        final width = height * (9 / 16);

        return ValueListenableBuilder<List<ZegoSDKUser>>(
          valueListenable: liveStreamingManager.coHostUserListNoti,
          builder: (context, cohostList, _) {
            final videoList = liveStreamingManager.coHostUserListNoti.value.map((user) {
              return ZegoAudioVideoView(userInfo: user);
            }).toList();

            return SizedBox(
              width: width,
              height: MediaQuery.of(context).size.height - kButtonSize - 150,
              child: ListView.separated(
                reverse: true,
                itemCount: videoList.length,
                itemBuilder: (context, index) {
                  return SizedBox(width: width, height: height, child: videoList[index]);
                },
                separatorBuilder: (context, index) {
                  return const SizedBox(height: 10);
                },
              ),
            );
          },
        );
      }),
    );
  }

  Widget startLiveButton() {
    return LayoutBuilder(
      builder: (context, containers) {
        return Padding(
          padding: EdgeInsets.only(top: containers.maxHeight - 110, left: (containers.maxWidth - 100) / 2),
          child: SizedBox(
            width: 100,
            height: 40,
            child: ElevatedButton(
              onPressed: startLive,
              child: const Text('Start Live', style: TextStyle(color: Colors.white)),
            ),
          ),
        );
      },
    );
  }

  void startLive() {
    liveStreamingManager.startLive(widget.roomID).then((value) {
      if (value.errorCode != 0) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('login room failed: ${value.errorCode}')));
      } else {
        ZEGOSDKManager.instance.expressService.startPublishingStream(liveStreamingManager.hostStreamID());
      }
    }).catchError((error) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('login room failed: $error}')));
    });
  }

  Widget leaveButton() {
    return LayoutBuilder(
      builder: (context, containers) {
        return Padding(
          padding: EdgeInsets.only(left: containers.maxWidth - 60, top: 40),
          child: CircleAvatar(
            radius: kButtonSize / 2,
            backgroundColor: Colors.black26,
            child: IconButton(
              onPressed: () {
                Navigator.pop(context);
              },
              icon: Image.asset('assets/icons/nav_close.png'),
            ),
          ),
        );
      },
    );
  }

  Widget memberButton() {
    return LayoutBuilder(
      builder: (context, containers) {
        return Padding(
          padding: EdgeInsets.only(left: containers.maxWidth - 60 - 53 - 10, top: 40),
          child: const ZegoMemberButton(),
        );
      },
    );
  }

  Widget hostText() {
    return ValueListenableBuilder<ZegoSDKUser?>(
      valueListenable: liveStreamingManager.hostNoti,
      builder: (context, userInfo, _) {
        return Padding(
          padding: const EdgeInsets.only(left: 20, top: 50),
          child: Text(
            'RoomID: ${widget.roomID}\n'
            'HostID: ${userInfo?.userName ?? ''}',
            style: const TextStyle(fontSize: 16, color: Color.fromARGB(255, 104, 94, 94)),
          ),
        );
      },
    );
  }

  Widget pkButton() {
    return Positioned(
      bottom: 80,
      right: 30,
      child: ValueListenableBuilder<RoomPKState>(
          valueListenable: ZegoLiveStreamingManager().roomPKStateNoti,
          builder: (context, roomPKState, _) {
            var text = '';
            if (roomPKState == RoomPKState.isNoPK) {
              text = 'PK Battle Request';
            } else if (roomPKState == RoomPKState.isRequestPK) {
              text = 'Cancel';
            } else if (roomPKState == RoomPKState.isStartPK) {
              text = 'End PK';
            }
            return ElevatedButton(
                onPressed: () {
                  pkClick(roomPKState);
                },
                child: Text(text));
          }),
    );
  }

  void pkClick(RoomPKState state) {
    switch (state) {
      case RoomPKState.isNoPK:
        startPK();
        break;
      case RoomPKState.isRequestPK:
        ZegoLiveStreamingManager().cancelPKBattleRequest();
        break;
      case RoomPKState.isStartPK:
        ZegoLiveStreamingManager().sendPKBattlesStopRequest();
        break;
    }
  }

  void startPK() {
    final editingController = TextEditingController();
    showCupertinoDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return CupertinoAlertDialog(
          title: const Text('Input a user id'),
          content: CupertinoTextField(controller: editingController),
          actions: [
            CupertinoDialogAction(
              onPressed: Navigator.of(context).pop,
              child: const Text('Cancel'),
            ),
            CupertinoDialogAction(
              onPressed: () {
                Navigator.of(context).pop();
                ZegoLiveStreamingManager().sendPKBattlesStartRequest(editingController.text).then((value) {
                  if (value.info.errorInvitees.map((e) => e.userID).contains(editingController.text)) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('start pk failed')));
                  }
                }).catchError((error) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('start pk failed')));
                });
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  void onExpressRoomStateChanged(ZegoRoomStateEvent event) {
    debugPrint('LivePage:onExpressRoomStateChanged: $event');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(milliseconds: 1000),
        content: Text('onExpressRoomStateChanged: reason:${event.reason.name}, errorCode:${event.errorCode}'),
      ),
    );
  }

  void onZIMRoomStateChanged(ZIMServiceRoomStateChangedEvent event) {
    debugPrint('LivePage:onZIMRoomStateChanged: $event');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(milliseconds: 1000),
        content: Text('onZIMRoomStateChanged: $event'),
      ),
    );
  }

  void onZIMConnectionStateChanged(ZIMServiceConnectionStateChangedEvent event) {
    debugPrint('LivePage:onZIMConnectionStateChanged: $event');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(milliseconds: 1000),
        content: Text('onZIMConnectionStateChanged: $event'),
      ),
    );
  }

  void onInComingRoomRequest(OnInComingRoomRequestReceivedEvent event) {}

  void onInComingRoomRequestCancel(OnInComingRoomRequestCancelledEvent event) {}

  void onOutgoingRoomRequestAccepted(OnOutgoingRoomRequestAcceptedEvent event) {
    applying.value = false;
    liveStreamingManager.startCoHost();
  }

  void onOutgoingRoomRequestRejected(OnOutgoingRoomRequestRejectedEvent event) {
    applying.value = false;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        duration: Duration(milliseconds: 1000),
        content: Text('Your request to co-host with the host has been refused.'),
      ),
    );
  }

  void showApplyCohostDialog() {
    ApplyCoHostListView().showBasicModalBottomSheet(context);
  }

  void refuseApplyCohost(RoomRequest roomRequest) {
    ZEGOSDKManager.instance.zimService
        .rejectRoomRequest(roomRequest.requestID ?? '')
        .then((value) {})
        .catchError((error) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Disagree cohost failed: $error')));
    });
  }

  void showPKDialog(String requestID) {
    if (showingPKDialog) {
      return;
    }
    showingPKDialog = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return CupertinoAlertDialog(
          title: const Text('receive pk invitation'),
          actions: [
            CupertinoDialogAction(
              child: const Text('Disagree'),
              onPressed: () {
                liveStreamingManager.rejectPKBattleRequest(requestID);
                Navigator.pop(context);
              },
            ),
            CupertinoDialogAction(
              child: const Text('Agree'),
              onPressed: () {
                liveStreamingManager.acceptPKBattleRequest(requestID);
                Navigator.pop(context);
              },
            ),
          ],
        );
      },
    ).whenComplete(() => showingPKDialog = false);
  }
}