# Lecture transcripts

Raw transcripts of Cristian Slav's course videos, as you shared them during preparation (attached files and text pasted into chat), cleaned of player timestamps and de-duplicated. One file per video. The study notes in `../notes/` are built from these.

**92 transcripts.**

Transcripts for the first batches that were pasted into chat (rather than attached) before the conversation was compacted could not be recovered, so a few early videos are missing here. Their content is still covered in the notes.


## Course introduction (5 videos)

- [Basic infrastructure that we need in order to develop the full verification](01-course-intro/01-basic-infrastructure-that-we-need-in-order-to-develop-the-fu.md)
- [Environment architecture so you will have a better image of what we will build](01-course-intro/02-environment-architecture-so-you-will-have-a-better-image-of-.md)
- [What is design verification](01-course-intro/03-what-is-design-verification.md)
- [Device under test, the DUT that we will use throughout this training in order](01-course-intro/04-device-under-test-the-dut-that-we-will-use-throughout-this-t.md)
- [What we will code](01-course-intro/05-what-we-will-code.md)

## APB agent (5 videos)

- [APB protocol checks](02-apb-agent/01-apb-protocol-checks.md)
- [Logic inside the APB driver](02-apb-agent/02-logic-inside-the-apb-driver.md)
- [This infrastructure of the APB agent](02-apb-agent/03-this-infrastructure-of-the-apb-agent.md)
- [APB sequence mechanism](02-apb-agent/04-apb-sequence-mechanism.md)
- [APB agent infrastructure](02-apb-agent/05-apb-agent-infrastructure.md)

## MD agent (14 videos)

- [Draw some conclusions about our MD agent](03-md-agent/01-draw-some-conclusions-about-our-md-agent.md)
- [Coverage related to the MD protocol](03-md-agent/02-coverage-related-to-the-md-protocol.md)
- [MD Master Driving Logic](03-md-agent/03-md-master-driving-logic.md)
- [MD protocol checks we already discussed about](03-md-agent/04-md-protocol-checks-we-already-discussed-about.md)
- [MD agent architecture](03-md-agent/05-md-agent-architecture.md)
- [MD master driving logic](03-md-agent/06-md-master-driving-logic-2.md)
- [MD protocol checks](03-md-agent/07-md-protocol-checks.md)
- [MD agent infrastructure](03-md-agent/08-md-agent-infrastructure.md)
- [MD slave Driving logic](03-md-agent/09-md-slave-driving-logic.md)
- [MD protocol](03-md-agent/10-md-protocol.md)
- [Coding the MD agent](03-md-agent/11-coding-the-md-agent.md)
- [MD monitor](03-md-agent/12-md-monitor.md)
- [Slave driving logic](03-md-agent/13-slave-driving-logic.md)
- [MD monitor](03-md-agent/14-md-monitor-2.md)

## UVM extension library (7 videos)

- [First class part of our UVM extension package, the Agent Configuration class](04-uvm-extension-library/01-first-class-part-of-our-uvm-extension-package-the-agent-conf.md)
- [Draw some conclusions about our UVM extension package](04-uvm-extension-library/02-draw-some-conclusions-about-our-uvm-extension-package.md)
- [UVM extension coverage class](04-uvm-extension-library/03-uvm-extension-coverage-class.md)
- [UVM extension driver](04-uvm-extension-library/04-uvm-extension-driver.md)
- [UVM extension agent](04-uvm-extension-library/05-uvm-extension-agent.md)
- [UVM extension agent class](04-uvm-extension-library/06-uvm-extension-agent-class.md)
- [An advanced technique for building UVM agents](04-uvm-extension-library/07-an-advanced-technique-for-building-uvm-agents.md)

## Register model (RAL) (15 videos)

- [Our discussion about the UVM register model](05-register-model/01-our-discussion-about-the-uvm-register-model.md)
- [How we can integrate the register block with the bus sequencer](05-register-model/02-how-we-can-integrate-the-register-block-with-the-bus-sequenc.md)
- [Register field callback](05-register-model/03-register-field-callback.md)
- [Custom Register Predictor](05-register-model/04-custom-register-predictor.md)
- [Register block](05-register-model/05-register-block.md)
- [Integration of the register block with the bus monitor](05-register-model/06-integration-of-the-register-block-with-the-bus-monitor.md)
- [How we can build a custom register predictor](05-register-model/07-how-we-can-build-a-custom-register-predictor.md)
- [UVM register](05-register-model/08-uvm-register.md)
- [Register field callback](05-register-model/09-register-field-callback-2.md)
- [Four register classes of the Aligner RTL](05-register-model/10-four-register-classes-of-the-aligner-rtl.md)
- [UVM register block](05-register-model/11-uvm-register-block.md)
- [Logic to integrate the register model with the APB Bus Monitor](05-register-model/12-logic-to-integrate-the-register-model-with-the-apb-bus-monit.md)
- [UVM register field](05-register-model/13-uvm-register-field.md)
- [Integration of the register block with our APB bus sequencer](05-register-model/14-integration-of-the-register-block-with-our-apb-bus-sequencer.md)
- [Draw some conclusions regarding our UVM register model](05-register-model/15-draw-some-conclusions-regarding-our-uvm-register-model.md)

## Modeling and checking (31 videos)

- [How we are going to model the legal RX accesses](06-modeling-and-checking/01-how-we-are-going-to-model-the-legal-rx-accesses.md)
- [How we are going to model the align logic](06-modeling-and-checking/02-how-we-are-going-to-model-the-align-logic.md)
- [Logic to model the TX Controller](06-modeling-and-checking/03-logic-to-model-the-tx-controller.md)
- [How we can solve the first synchronization issue in our model regarding the](06-modeling-and-checking/04-how-we-can-solve-the-first-synchronization-issue-in-our-mode.md)
- [DUT functional coverage](06-modeling-and-checking/05-dut-functional-coverage.md)
- [Fix for our push and pop synchronization issue from our model](06-modeling-and-checking/06-fix-for-our-push-and-pop-synchronization-issue-from-our-mode.md)
- [Fix together the synchronization issue from our model regarding the FIFO flags](06-modeling-and-checking/07-fix-together-the-synchronization-issue-from-our-model-regard.md)
- [How we can fix the push and pop synchronization issue in our model](06-modeling-and-checking/08-how-we-can-fix-the-push-and-pop-synchronization-issue-in-our.md)
- [Model for the align logic](06-modeling-and-checking/09-model-for-the-align-logic.md)
- [Our last model synchronization issue regarding overlapping interrupt requests](06-modeling-and-checking/10-our-last-model-synchronization-issue-regarding-overlapping-i.md)
- [Scoreboard Architecture](06-modeling-and-checking/11-scoreboard-architecture.md)
- [Fix for our last model synchronization issue regarding overlapping interrupt](06-modeling-and-checking/12-fix-for-our-last-model-synchronization-issue-regarding-overl.md)
- [Logic which will model our intermediate buffer](06-modeling-and-checking/13-logic-which-will-model-our-intermediate-buffer.md)
- [How we are going to model the TX Controller logic](06-modeling-and-checking/14-how-we-are-going-to-model-the-tx-controller-logic.md)
- [How we are going to model the intermediate buffer logic](06-modeling-and-checking/15-how-we-are-going-to-model-the-intermediate-buffer-logic.md)
- [RX response scoreboard check](06-modeling-and-checking/16-rx-response-scoreboard-check.md)
- [Model for the legal RX Accesses](06-modeling-and-checking/17-model-for-the-legal-rx-accesses.md)
- [What components we are going to implement in this "Modeling and Checking"](06-modeling-and-checking/18-what-components-we-are-going-to-implement-in-this-modeling-a.md)
- [Model architecture](06-modeling-and-checking/19-model-architecture.md)
- [Model interface](06-modeling-and-checking/20-model-interface.md)
- [Input and output ports of our Model class](06-modeling-and-checking/21-input-and-output-ports-of-our-model-class.md)
- [How we can model the illegal RX accesses](06-modeling-and-checking/22-how-we-can-model-the-illegal-rx-accesses.md)
- [Scoreboard interface](06-modeling-and-checking/23-scoreboard-interface.md)
- [How we are going to implement the scoreboard check regarding the RX response](06-modeling-and-checking/24-how-we-are-going-to-implement-the-scoreboard-check-regarding.md)
- [How we are going to implement the TX item scoreboard check](06-modeling-and-checking/25-how-we-are-going-to-implement-the-tx-item-scoreboard-check.md)
- [How we are going to implement the interrupt request scoreboard check](06-modeling-and-checking/26-how-we-are-going-to-implement-the-interrupt-request-scoreboa.md)
- [Scoreboard check for the interrupt request](06-modeling-and-checking/27-scoreboard-check-for-the-interrupt-request.md)
- [Implementing the DUT functional coverage](06-modeling-and-checking/28-implementing-the-dut-functional-coverage.md)
- [Virtual sequencer](06-modeling-and-checking/29-virtual-sequencer.md)
- [Virtual sequencer](06-modeling-and-checking/30-virtual-sequencer-2.md)
- [Draw some conclusions about our modeling and checking section](06-modeling-and-checking/31-draw-some-conclusions-about-our-modeling-and-checking-sectio.md)

## Debug and tests (13 videos)

- [How we can update our random traffic test to make it more random](07-debug-and-tests/01-how-we-can-update-our-random-traffic-test-to-make-it-more-ra.md)
- [Tests organization](07-debug-and-tests/02-tests-organization.md)
- [Our illegal RX traffic test](07-debug-and-tests/03-our-illegal-rx-traffic-test.md)
- [Update the register access test to make it more random](07-debug-and-tests/04-update-the-register-access-test-to-make-it-more-random.md)
- [How we can update our register access test to make it more random](07-debug-and-tests/05-how-we-can-update-our-register-access-test-to-make-it-more-r.md)
- [A very useful debug feature of the UVM library called UVM Transactions](07-debug-and-tests/06-a-very-useful-debug-feature-of-the-uvm-library-called-uvm-tr.md)
- [This UVM message system so that we can use this feature to help us with debug](07-debug-and-tests/07-this-uvm-message-system-so-that-we-can-use-this-feature-to-h.md)
- [Update our random traffic test to make it more random](07-debug-and-tests/08-update-our-random-traffic-test-to-make-it-more-random.md)
- [A debug technique which I called "Track the source"](07-debug-and-tests/09-a-debug-technique-which-i-called-track-the-source.md)
- [UVM messages and in particular how this feature will help us with debug](07-debug-and-tests/10-uvm-messages-and-in-particular-how-this-feature-will-help-us.md)
- [What we will learn in this "Debug and Tests" section](07-debug-and-tests/11-what-we-will-learn-in-this-debug-and-tests-section.md)
- [How we can implement our illegal RX traffic test](07-debug-and-tests/12-how-we-can-implement-our-illegal-rx-traffic-test.md)
- [Draw some conclusions about our "Debug and Tests" section](07-debug-and-tests/13-draw-some-conclusions-about-our-debug-and-tests-section.md)

## Finish line (2 videos)

- [Stages of a verification project](08-finish-line/01-stages-of-a-verification-project.md)
- [Rd me say this more than 100 times during this training. In this final video I j](08-finish-line/02-rd-me-say-this-more-than-100-times-during-this-training-in-t.md)
