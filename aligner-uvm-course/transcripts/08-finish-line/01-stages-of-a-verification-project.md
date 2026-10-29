# Stages of a verification project

*Chapter: Finish line · source: attached*

Hi!
My name is Cristian Slav and in this tutorial we are going to talk about the stages of a verification project.
When you start a verification project, the first thing that you have to do is to understand the DUT specifications.
This means that you have to read and understand all the documents which are describing the expected behavior of the DUT that you have to verify.
When you are at this stage and you try to understand the expected behavior of a DUT, some of the things that you read from the documents will not be clear to you.
And my strong recommendation to you is that at this point don't be afraid to ask questions.
The right person to ask these questions is the author of the documents that you are reading.
So, most of the times this will be the concept engineer.
The responsibility of the concept engineer is to come up with all the features that are required by your DUT in order to work correctly at system level.
So, if you don't understand something from the documentation, the concept engineer is the right person for you to ask these questions.
You don't want to get in a scenario in which you thought you understood correctly a feature of a DUT and then you invested a lot of time and effort to implement that feature in your model just to realize later that your understanding was wrong.
So, ask questions at this stage before you write any line of code.
Don't be afraid of what they will think about your questions, just ask the questions, it's better to understand everything clearly now.
Once you understood perfectly the DUT specifications then you move to the next stage in which you have to implement the verification documents.
The documents required at this stage may vary from company to company but in general you will need to create two documents.
In the first one, usually it's a simple Word document, in which you have to describe the architecture of the verification environment.
So in this document you'll have to put the diagram of your environment with all the components part of the environment, you'll have to create UML diagrams showing the API of all the classes in your environment and how the objects in your environment communicate.
My recommendation to you is to try to add in this document as many details as you can think about.
In this way, you'll have a clear picture of what you need to do when you start coding the environment.
The second document that you'll have to create is the verification plan.
Remember, the verification plan is that tree-like structure that we talked about when we discussed the coverage.
There are specific tools from vendors or even developed by each company to build these verification plans.
And beside the coverage that you want to develop for your verification environment, you can also put in this verification plan also the checks and the tests that you plan to develop.
For each document that you have to implement at this stage, you'll have to follow these steps.
First, you have to write the document, and then you have to organize a review for that document.
If there are any action items for you at the end of the review, you'll have to implement those in your document and then maybe have a second review on the final version of your document.
The audience for reviewing the documentation will vary based on the nature of the document.
For example, for the document describing the architecture of the verification environment, you can review that document with all the verification engineers part of your team.
However, for the verification plan, the audience must be made out of verification engineers, design engineers, and concept engineer.
This is because at the end of the verification plan review, everybody needs to be aware of what will be covered and verified by your verification environment.
So this is why it's important that beside the verification team, also design and concept participate in this review.
In this way, you minimize the risk of omitting from verification some of the features of the DUT.
During the review, the design or the concept engineers can step in and raise this problem.
Once you finish implementing and reviewing all the documents, then you start to develop the verification environment.
And throughout this training, you learned what it takes to implement this step correctly.
Once you have your verification environment complete, then you start running regressions.
Remember, a regression means running all your tests with random seeds many many times.
When you are running regressions, you will have two goals.
Your first goal is to have all your tests passing 100%.
This means that regardless of how many tests you will have in your regressions, all of them will pass.
After that, your second goal is to hit 100% coverage.
And there are two coverage metrics that you will have to hit.
The first one is the functional coverage.
This is the coverage that you will implement in your verification environment.
And the second one is code coverage.
This metric will tell you information like what lines of RTL code were used during the regressions, how expressions from the RTL were covered, state machine transitions, and so on.
Analyzing the functional coverage is the responsibility of the verification engineer and for code coverage the responsibility belongs to the design engineers.
From the missing coverage you might come to the conclusion that you have to add more tests in your regressions.
So this means that you might have a loop like this one.
Based on the missing coverage you will implement new tests and when you run those tests some of them will fail and you will continue this iteration until you hit 100% passing rate and 100% coverage.
So, these are the basic criterias for knowing when the verification ends.
However, you might encounter another requirement that you'll have to fulfill in order to complete verification.
And this implies running a verification environment qualification.
In this step, you'll have to run specific tools which will evaluate the quality of your verification environment.
The way this evaluation works, it's pretty smart.
You provide to these tools your verification environment together with the DUT that you verified.
And what they will do is to automatically inject in the DUT bugs.
For example, they will inject errors like negating a signal or disconnecting a signal and so on.
And for each bug that they will inject in the DUT, they will run your regressions and see if your verification environment detects that bug.
So, based on the results coming from these qualification tools, you'll have to update your environment in order to catch those bugs.
So, you'll have some iterations through these stages until everything is clean.
Once you reach all these goals for ending the verification, then you move to the last stage in which you sign off your verification.
This means that you have to generate some reports which will prove that you completed the verification of that DUT.
These reports vary from company to company, but in general, they will have to contain coverage information and the tests and seeds used to obtain that coverage.
Throughout this training, most of our focus was on this stage where we developed the verification environment.
On the EDA Playground platform we currently don't have any mechanism for running regressions.
But you saw that even by manually running a particular test many times we managed to find seeds for which the test failed.
Even though we fixed those RTL bugs, because we don't have a regression mechanism we cannot be sure that there are no other bugs in our RTL or in our environment.
So just be aware of this and if you manage to get a failing test with either an RTL or environment bug, please share with us this information.
That's it for this tutorial.
We went through all the stages of a verification project and I hope now it's a bit clearer for you what is expected from a verification engineer.
Thanks for watching and see you in our last video.
Bye!
