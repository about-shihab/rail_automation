import 'package:flutter/material.dart';

import '../services/booking_activity.dart';
import '../services/language_service.dart';
import '../services/turnstile_gate.dart';
import '../services/turnstile_session.dart';
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
        // The existing verification route must stay accessible, including its
        // checkbox, error/retry and cancel controls. Reuse its train animation.
        final show =
            work.busy &&
            !session.generating &&
            !TurnstileGate.instance.isPresenting;
        return Stack(
          children: [
            child,
            if (show) ...[
              const Positioned.fill(
                child: ModalBarrier(
                  key: ValueKey('booking-api-barrier'),
                  dismissible: false,
                  color: Colors.black54,
                ),
              ),
              Positioned.fill(
                child: SafeArea(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: FancyTrainLoader(
                          showCard: true,
                          stage:
                              work.stage == BookingActivityStage.searching ||
                                  work.stage == BookingActivityStage.tickets
                              ? JourneyAnimationStage.searching
                              : work.stage == BookingActivityStage.verifying
                              ? JourneyAnimationStage.verifying
                              : JourneyAnimationStage.reserving,
                          message: LanguageService.instance.tr(
                            work.stage == BookingActivityStage.searching
                                ? 'Finding your trains'
                                : work.stage == BookingActivityStage.tickets
                                ? 'Loading your tickets'
                                : work.stage == BookingActivityStage.layout
                                ? 'Loading available seats'
                                : work.stage == BookingActivityStage.verifying
                                ? 'Verifying your OTP'
                                : 'Reserving your tickets',
                            work.stage == BookingActivityStage.searching
                                ? 'আপনার ট্রেনের খোঁজ করা হচ্ছে'
                                : work.stage == BookingActivityStage.tickets
                                ? 'আপনার টিকিটের তথ্য আনা হচ্ছে'
                                : work.stage == BookingActivityStage.layout
                                ? 'আসনের তথ্য আনা হচ্ছে'
                                : work.stage == BookingActivityStage.verifying
                                ? 'OTP যাচাই করা হচ্ছে'
                                : 'আপনার আসন রিজার্ভ করা হচ্ছে',
                          ),
                          subMessage: LanguageService.instance.tr(
                            'Waiting for the Railway response…',
                            'রেলওয়ের উত্তর পাওয়ার অপেক্ষায়…',
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
