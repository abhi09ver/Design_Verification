# This UVM message system so that we can use this feature to help us with debug

*Chapter: Debug and tests · source: attached*

Hi!
My name is Cristian Slav and in this tutorial we are going to implement this UVM message system so that we can use this feature to help us with debug.
The first thing that we will do is to update all the messages in our environment to use these IDs and as verbosity we will set the corresponding verbosity based on these tables.
Once we have that, we will add an F-file to our project so that we can add commands to filter out the messages based on our needs.
The starting point is the EDE Playground project called "UVM Messages - Practice" which we need to copy.
And now let's resize the windows.
First we will update the messages from our UVM extension package.
So we have a message here at line 91 and this is a configuration message so we need to update the ID to value CONFIG.
Also verbosity to UVM_FULL.
And let's also fix the message as it has this APB here.
Also in this file we have another message down below here.
This is the coverage message, so we need to put the ID COVERAGE and verbosity UVM_DEBUG.
Next, let's go to our APB package and here we have some messages down at line 254 here so this is a message printed at the end of the item so we need to put the ID ITEM_END and then verbosity UVM_LOW.
And we also have a message from the driver at line 459, here so this one it's at the start of the item, so we need to put the ID ITEM_START and also verbosity UVM_LOW.
Let's update in the same way the messages from the MD package.
This is a message from the beginning of an item which is currently commented out, but we can put it back in with ID ITEM_START and verbosity UVM_LOW.
Next, we have a message at 355, so this message is printed at the end of the item, so it will have the ID ITEM_END and verbosity UVM_LOW.
Now let's go to line 627 and here we will use ID ITEM_START and verbosity UVM_LOW.
And we have one last message from this package at 716 here.
That's it with this package and now let's jump to our model class.
And here the first message is at line 191.
So this message is printed when the drop counter reach its maximum value so we need to put the id CNT_DROP and verbosity medium.
Next, we have a message at 212, so this one is related to RX FIFO when it became full, so it will have ID RX_FIFO and verbosity medium.
At line 237 we will use the same ID RX_FIFO and the same verbosity UVM_MEDIUM.
The same thing here for the TX FIFO.
So here the ID is TX_FIFO.
And the same thing here.
The next message is at 351, this one.
This is related to count drop when it is incremented.
So we will use the ID CNT_DROP and verbosity UVM_LOW.
Next we have a message at 505.
This message shows when there is a push action in our RX FIFO, so we will use ID RX_FIFO and verbosity UVM_LOW.
The same thing for the pop action from here.
And now for the TX FIFO.
That's it with all the messages from our model.
And now let's jump to this clr_cnt_drop.
And for this message printed when the counter is cleared we can use id CNT_DROP and verbosity high.
That's it.
And now let's jump to this aligner coverage at line 98.
Here we have our message to print the coverage so we can use the ID COVERAGE and verbosity UVM_DEBUG.
Next, let's jump to the environment configuration class.
Here this is a configuration message so it should have the ID CONFIG, verbosity full and we should also fix this typo.
Next, let's jump to our test random and at line 57.
This is at the end of the test and we are already getting messages at the end of the test from the UVM library so we can delete this line.
And the same thing in the reg_access test here.
That's it.
So we've updated all the messages and now let's create that .f file so we can create a new file from here and let's call it messages.f.
And we can add this file to our project by going to "Tools & Simulators" in the "Run Options".
First we can get rid of this command for printing the REG_PREDICT messages.
And now we can add this file with -f option.
That's it.
And now let's add some commands in this messages.f file to see how these are influencing our log.
First, let's add a command which will disable all the messages.
That's it.
So this command will influence the messages from all the components with all the IDs.
So this is the keyword for selecting all the IDs.
And we want to enable only the messages with verbosity UVM_NONE.
So we don't have any message with verbosity UVM_NONE so nothing will be printed.
And this will be applied from time 0.
So let's save and run our test to see how the log looks like after this command.
The simulation finished and now if we look through the log we are not getting any messages from our environment.
Now let's add a command which will enable only the messages related to the RX FIFO feature with verbosity medium.
That's it and now let's save and run.
The simulation finished and now let's look through the log.
And you can see that only the messages with ID RX_FIFO were printed.
And this is very useful if we are debugging some failing test which is failing due to some RX FIFO issue.
And you can see here only the messages for the RX FIFO that was a push, then a pop and then the FIFO became empty and the same thing repeated over and over again.
And these messages also confirm our slow pace sequence in which we are pushing one entry in the RX FIFO and then we wait for that entry to go out on the TX interface.
So first we push, then the RTL popped that information from the FIFO and the FIFO became empty.
And then again the push, the pop, and FIFO became empty.
Now, let's add one more filter to our messages.
Let's enable the messages with ID REG_PREDICT and verbosity high or lower.
And let's also enable the messages from our MD monitors with ID ITEM_END and verbosity UVM_LOW or lower.
And before that we can comment this line so the comment will also apply to this F-file like so.
That's it.
So with this command I'm enabling the messages to show when our reg model is updated.
And with this command I'm enabling the messages from our MD monitors and only for the ID ITEM_END.
And now let's save and see how our log looks like.
That's it.
The simulation finished.
First, we can look at this report generated by the UVM library and we can see from this report that our commands worked.
This report shows how many messages with different IDs were printed and we can see our ITEM_END ID and our REG_PREDICT.
And let's see how our log looks like with our new filter.
So now the log is pretty clean.
First we can see the writes to our registers and then the messages printed with ID ITEM_END from our monitors.
So, first we have an ITEM_END on the RX interface and the data is this one, so 4 bytes and these bytes are outputted on the TX interface.
So, this 0B from here, then A1, 81, and 60.
And then again, a message from the RX monitor followed by the messages from the TX monitor.
So, in this way, the log is pretty clean, we are only seeing what is happening on the interfaces of our RTL.
And then when we have a test which fails, we can enable different messages based on the error that we get.
And we can do this in our new messages.f file.
That's it for this tutorial.
We managed to update all the messages from our environment in order to filter out the messages printed in the log using this +uvm_set_verbosity command.
I hope everything was clear for you, thanks for watching and see you in the next tutorial.
Bye!
