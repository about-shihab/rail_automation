import 'package:flutter/material.dart';

import '../services/booking_activity.dart';
import '../services/language_service.dart';
import '../services/turnstile_gate.dart';
import '../services/turnstile_session.dart';
import '../views/reservation_screen.dart';
import 'fancy_train_loader.dart';

class BookingActivityOverlay extends StatelessWidget {
  const BookingActivityOverlay({super.key, required this.child, this.activity});
  final Widget child;
  final BookingActivity? activity;

  @override
  Widget build(BuildContext context) {
    final work = activity ?? BookingActivity.instance;
    final session = TurnstileSession.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([work, session, LanguageService.instance]),
      builder: (context, _) {
        // Only show overlay for initial search, coach layout, and ticket loading.
        // NEVER show a modal barrier for reserving or verifying, which have their own
        // dedicated in-screen progress state and must never block the user from entering OTP.
        const allowedStages = {
          BookingActivityStage.searching,
          BookingActivityStage.layout,
          BookingActivityStage.tickets,
        };
        final isReservationOpen =
            work.isReservationActive || ReservationScreen.isActive;
        final show =
            work.hasForegroundOperations &&
            allowedStages.contains(work.stage) &&
            !isReservationOpen &&
            !session.generating &&
            !TurnstileGate.instance.isPresenting;

        if (!show) {
          return child;
        }

        return Stack(
          children: [
            child,
            Positioned.fill(
              child: ModalBarrier(
                key: const ValueKey('booking-api-barrier'),
                dismissible: true,
                onDismiss: () => work.reset(),
                color: Colors.black45,
              ),
            ),
            Positioned.fill(
              child: SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          FancyTrainLoader(
                            showCard: true,
                            stage: JourneyAnimationStage.searching,
                            message: LanguageService.instance.tr(
                              work.stage == BookingActivityStage.searching
                                  ? 'Finding your trains'
                                  : work.stage == BookingActivityStage.tickets
                                  ? 'Loading your tickets'
                                  : 'Loading available seats',
                              work.stage == BookingActivityStage.searching
                                  ? 'আপনার ট্রেনের খোঁজ করা হচ্ছে'
                                  : work.stage == BookingActivityStage.tickets
                                  ? 'আপনার টিকিটের তথ্য আনা হচ্ছে'
                                  : 'আসনের তথ্য আনা হচ্ছে',
                            ),
                            subMessage: LanguageService.instance.tr(
                              'Waiting for the Railway response…',
                              'রেলওয়ের উত্তর পাওয়ার অপেক্ষায়…',
                            ),
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Material(
                              type: MaterialType.transparency,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () => work.reset(),
                                child: Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: Icon(Icons.close, size: 20, color: Colors.grey.shade600),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
