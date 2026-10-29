# UVM messages and in particular how this feature will help us with debug

*Chapter: Debug and tests · source: attached*

Hi!
My name is Cristian Slav and in this tutorial we are going to talk about the UVM messages and in particular how this feature will help us with debug.
We already made use of the UVM messages in our environment via this macro `uvm_info.
As you know this macro has three arguments.
The first one ID it's a string.
In the second one we are putting the message that we want to be printed and the third one is the verbosity.
So far in most of the cases in our environment, we use for ID the value "DEBUG" and for verbosity we used UVM_NONE.
But we can make use of this ID and VERBOSITY to filter out all the messages which are not relevant for the test that we want to debug.
As you already know, the ID can be any string that we want to put here.
But for VERBOSITY, we have several options.
In the UVM documentation, you can find these values for the UVM verbosity: none, low, medium, high, and full, but there is another one, UVM_DEBUG, which I don't know why is not listed in the documentation, but it is there.
The UVM library comes with some commands that we can pass to the simulator in order to filter the messages based on several criterias: the ID, the verbosity, and the full name of the component from which we are printing that message.
The command through which we can control the messages is this one: +uvm_set_verbosity.
It has two options.
In the first option, we can specify the component, meaning the full name of the component from which we want to control a message, then the ID of the message, the verbosity, and finally the UVM phase in which we want to apply this command.
So this can be run phase or build phase and so on.
In the second option, and this is the one that we will use, we can still specify the component, the full name of the component, the ID, the verbosity, and then through this "time" option here we can specify the time from which this command should be applied.
And let's see how we can apply this command.
So, in our monitor from the MD package, at the end of the collect_transaction() task we have this message: "Monitored item:" and the value of the item that our monitor collected.
We can set for this message its ID to be ITEM_END, as this is the information printed at the end of the item.
And then as verbosity, we can put here UVM_LOW.
Remember that we have two instances of this MD monitor, one for RX and one for TX.
And for example, if we want to control the message from the RX monitor, we can call this command in this manner.
For this +uvm_set_verbosity we can pass the full name of the component from which we want to control that message and in this case we want to target the monitor from the RX agent.
Then we specify the ID ITEM_END so this one will be the same as the string that we have here.
We specify the verbosity UVM_LOW and then for time we pass the value 0 meaning that we want to apply this command from time 0.
And what this command does is to enable all the messages with ID ITEM_END, verbosity UVM_LOW or lower so also the messages with verbosity UVM_NONE will be affected by this command.
This command will affect the messages from this component only and it will be applied from time 0.
When we specify the component we can also use the * notation.
So for example, if we want to apply this command for the messages from the RX and TX monitors then we use * here.
However, this * notation does not apply to the ID argument.
So, for the ID you have to specify exactly the value that you set for the message in your code.
However, there is a keyword which will affect all the IDs and this one is _ALL_.
So, when you use this special value for the ID it means that you want to apply this command to all the IDs in your code.
So this is equivalent with a * notation here.
We can actually put all these commands into a single file, usually called an F file.
Most of the simulators will have the same syntax to pass this file to the simulator: -f and then the path to your file.
And in that file you can put as many commands as you want and they will be applied sequentially.
So for example, we can first use this command to disable all the messages and then we can put this command to enable only the messages with ID ITEM_END, verbosity UVM_LOW or lower from the RX agent.
In our practice session, we will create such a file and we will add there several of these commands.
The UVM documentation does not really offer some guidelines in how you can use the ID and verbosity to create a message system that you can make use of when you are debugging.
So this will be up to you to create your own system in controlling your messages.
But I can share with you the way I'm using this feature of the UVM library in order to control the messages in my environment.
And what I'm doing it's pretty simple, I'm creating a table like this one for all the IDs in my environment.
So, in the header of the table, I have the ID for which I want to specify what messages I want to be printed in my environment.
And then for each verbosity, I have a short description to help me know which verbosity I have to assign to a particular message.
And one important thing is that I never use UVM_NONE as verbosity for a message.
This will allow me to disable the messages for this particular ID or for example all the messages from my environment.
Now, let's see how these tables will look like for all the messages from our environment.
First, we can have an ID called ITEM_START.
We can use this ID to print some information when we start an item from the monitor or from the driver.
And we can use UVM_LOW as its verbosity.
In our case, we have three agents: APB, MD RX, and MD TX.
So, in all these agents, we will use this ID: ITEM_START.
We can apply the same logic for the messages printed at the end of the item.
The same verbosity, UVM_LOW, and the same thing we can use this ID to print messages at the end of the item in the monitor or in the driver.
Next, we have several messages from our model.
We can use the ID RX_FIFO to print messages relevant for our RX FIFO feature.
For the verbosity UVM_LOW, we can print messages which are showing some push and pop actions.
For the medium verbosity, we can print messages which will show us if the FIFO became full or empty.
So this will be relevant when we are debugging the interrupt requests.
We can do the same thing for the TX FIFO.
The last ID in our model will be this CNT_DROP, and we can use this ID to print messages relevant to that drop counter.
For the low verbosity, we will print messages when we increment this counter.
For the medium verbosity, we will print the message when this counter reaches its maximum value.
And with the high verbosity, we will print the message when we are clearing this counter.
The next ID that we can use is this COVERAGE ID.
Remember that we have some code to print the coverage information, and for those messages, we can use this ID, and as verbosity, we can use the debug value.
The last ID that we can use is this CONFIG ID, as we have some messages printed when we are configuring the agents or our environment.
So this will be a one-time-only configuration message, and we can use as verbosity the value UVM_FULL.
So I'm trying to organize the messages based on the features of the RTL and also I'm trying to control the messages from the agents.
If you want to read more about this subject, you can go to the UVM User Guide and in the section "Advanced Topics", "Command Line Interface", and then here "UVM-aware Command Line Processing", you have this chapter "Setting Verbosity" in which you can read more about this +uvm_set_verbosity command.
In the UVM Class Reference, you have several sections.
First, under "Macros and Defines", you have this "Report Macros" and in here you can find more information about this `uvm_info.
Another relevant section from the UVM Class Reference manual it's under "Command Line Processor" here and if you scroll down you can get more information about this +uvm_set_verbosity.
One other source of information that I want to share with you is an article that I wrote called "System Verilog Tip: How to do logging in UVM".
And in here I'm talking about an issue that you'll probably encounter in your career.
Sometimes you might want to assign to the same message different IDs with the same or different verbosities.
This is currently not supported by this `uvm_info macro but I actually created a new macro which will help you with this.
So this means that in your code you can do something like this `uvm_infos and then here you can specify multiple IDs for the same message and you can assign for example different verbosities for each of these IDs.
To get this in your project you simply have to add this macro to your code.
That's it for this tutorial.
We talked about how to control the messages, how to organize the messages based on ID and verbosity, and we also looked through the documentation to see where you can find more information on this subject.
In the next tutorial, we will implement together all these in our project.
Thanks for watching and see you in the next tutorial.
Bye!
