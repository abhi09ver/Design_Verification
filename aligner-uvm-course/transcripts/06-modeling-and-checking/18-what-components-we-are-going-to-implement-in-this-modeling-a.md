# What components we are going to implement in this "Modeling and Checking"

*Chapter: Modeling and checking · source: pasted in chat*

Hi!
My name is Cristian Slav and in this introduction tutorial we are going to talk about what components we are going to implement in this "Modeling and Checking" section of our training.
This is how our environment looks so far and the first thing that we are going to implement is the model.
The job of the model is to take the values from the inputs of the RTL and generate expected results for the outputs of the RTL.
So, in the Aligner case, whenever our RX agent generates some sequences to send to the Aligner RTL, that information will be sent to the RTL, but the monitor will pick it up and also send it to our model.
At this point it's time to introduce the second component which we will have to implement and that is the scoreboard.
The job of the model as I told you is to generate the expected outputs of the Aligner RTL.
So for the MD RX interface the output of the RTL is the response return for any MD transaction on the RX interface.
So this is what our model will generate, an expected response on the MD RX interface and it will send that response to the scoreboard.
And also our RTL will generate a response which will be picked up by our agent and also sent to the scoreboard.
And here the job of the scoreboard is to compare the two responses, the one from the RTL and the one from the model.
And if there is a difference between these two it will trigger an UVM error.
So that's the first output that our model will generate, the expected response on the RX interface.
And after that our model and also the Aligner will start to process this MD RX information.
So both of these entities, the model and the RTL, will perform the alignment function.
And once our model generated this aligned information, it will send it to the scoreboard as this is the expected output of the Aligner on the TX interface.
Of course, the RTL should do the same thing and that information will be picked up by the TX agent and also sent to the scoreboard.
And once again here the scoreboard will compare the two informations, the one from the model and the one from the RTL.
And if there is a mismatch, it will again trigger an UVM error.
And RTL has one more output which we will have to verify and that one is not represented here.
I'm talking about the interrupt requests.
So just to recap, the job of the model is to generate the expected outputs of the RTL based on the inputs which goes into the Aligner.
And there are three of these outputs: the response on the MD RX interface, the output transaction on the TX interface, and the interrupt requests.
The model sends this expected information to the scoreboard and the scoreboard will compare that information with whatever RTL is outputting.
And this is how we catch bugs in the RTL.
Once we finish implementing the model and the scoreboard, the next component that we will implement is the coverage.
The coverage from the environment is responsible for keeping track of all the scenarios in which we tested so far our Aligner.
The last component that we will implement is this virtual sequencer.
And this component help us implement virtual sequences with which we can control sequences for our three agents.
That's it for this tutorial.
We discussed what components we will build in this section and what is the role of each of those components.
And in the next tutorial we will start implementing that model component.
Thanks for watching and see you in the next tutorial.
Bye!
