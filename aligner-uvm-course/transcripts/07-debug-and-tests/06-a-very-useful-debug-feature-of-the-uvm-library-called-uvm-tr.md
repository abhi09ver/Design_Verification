# A very useful debug feature of the UVM library called UVM Transactions

*Chapter: Debug and tests · source: attached*

Hi!
My name is Cristian Slav and in this tutorial we are going to talk about a very useful debug feature of the UVM library called UVM Transactions.
Before we go into the details of these UVM transactions, first let's understand the problem that this feature of the UVM library aims to solve.
This is a snapshot of the waveforms that we usually see from our random test.
And just by looking on this image is quite difficult to understand what exactly is happening in our Aligner RTL.
Even if we zoom in a little bit, we have to know exactly the APB and the MD protocol to make sense of what is happening on the waveforms.
We can see on the APB interface that we have an access to address F0 and in order to know its direction we have to look on this signal to know if it is a read or a write access and also on the MD interface we have to know the protocol in order to figure out that the valid data that we want to transmit in this transaction is this 34AB.
And this is based on the size and the offset signals that we have here.
The APB and MD protocols are quite simple and with a little bit of practice, you can figure out what is happening on the waveforms.
But there are protocols in which it's very difficult to figure out what is happening just by looking on the waveforms.
And in particular, if you have a serial protocol like I2C, it will be extremely difficult to figure out what information is transmitted on the signals just by looking on the waveforms.
This is exactly the problem which we can solve with UVM transactions.
This feature of the UVM library offers us an alternative when looking on the waveforms.
Instead of looking at the signals part of a particular protocol, we can actually look at something like this.
We can have these bubbles in which we can put information which will help us understand quickly what is happening on the waveforms.
So, for example, instead of seeing these signals part of the APB protocol, we can see a bubble like this one with all the relevant information for us.
We know immediately that this is a write access to address F0 and data 1F.
And for the MD protocol we can see the information formatted like this.
We can see the offset and the data and from this list representation of the data we can immediately determine the size of the transaction and we can also have here the response.
We can take this representation one step further and instead of the APB information, we can put in these bubbles the register access information.
We can immediately see what register was accessed, with what direction, and what are the new values of the fields inside the register.
So, this way of visualizing the waveforms makes us understand much quickly what is happening in our test than just looking on the signals of the protocols.
To enable this feature in our environment is relatively easy.
I will show you next the steps that you need to take in order to have something like this in your environment.
However, at the time when I am recording this tutorial, the EDA Playground platform does not support this feature in the waveforms viewer.
So, because of this reason, we will not have a practice session in which we will implement and see on the waveforms this feature.
But most of the simulators do support this feature, so I will show you exactly how you can configure this in your project.
The first thing that you need to know is that this feature is possible due to a class in the UVM library called uvm_transaction.
And if you look in the UVM documentation, you'll see that this uvm_transaction is a parent class of the uvm_sequence_item.
And in our environment, we use this uvm_sequence_item as the base class for all the classes that we are using in our driver and monitor.
So our items from the APB and the MD packages will have in their inheritance tree this uvm_transaction.
So this means that we already have access to the API with which we can enable this feature.
So let's see exactly what we need to configure in our environment to make use of the UVM transactions.
First, we need to define what kind of information we want to see in these bubbles.
This is quite easy to configure and we have multiple options to do this.
One way is to override the function do_record().
This function has an argument called recorder and we can make use of the API of this uvm_recorder to configure the information from these bubbles.
For example, if we want to record a field which is of type int, then we call this function record_field(), we pass here a string, so the string from here, it will be this one displayed here.
Then we pass the value, then the width of this field in bits.
For displaying the data, we can actually pass to this recorder a string.
We can format the data in any way we want.
For example, this get_data_as_string() can return the information from the data list in this format.
And of course, the same thing we can do for the response information from our item.
But as I told you, we have several possibilities to specify what information we want to have in these bubbles.
And another alternative is to make use of the UVM macros.
We can do this with these `uvm_field_* macros.
So instead of our regular `uvm_object_utils, we can put here `uvm_object_utils_begin and an end here, and in between we can call `uvm_field_* macros, and we have macros based on the types of the fields that we want to configure.
For example, our offset is an integer, so we will call this `uvm_field_int macro.
Our data is a queue, so we will call this macro.
Our response is an enumerated type, so we can call this macro, and so on.
To specify to the UVM library that we want these fields to be recorded in these bubbles, the next argument that we use for these macros should be this UVM_RECORD.
You have multiple options to put here, not just UVM_RECORD.
You can put UVM_COPY, UVM_CLONE, and so on.
I'll let you go through the documentation on your own to see exactly what are all the options that you can use here.
Of course, when you are using these macros, the UVM library will format for you the information displayed in these bubbles.
And because of this reason, my preferred way is to override this do_record() function and format on my own the information that I want to see in these bubbles.
Once we define the information that we see in these bubbles, then we need to go to our monitor.
Remember that in our collect_transaction(), the first thing that we do is to wait for an item to start.
Once we detect the beginning of an item, then we should call this function enable_recording().
To this function, we need to pass a transaction stream.
Directly from our monitor, as it is inheriting from the uvm_component class, we can call this function get_tr_stream() and pass here a string.
The string that we will put here is exactly the string that we will see in our data browser when we look for this transaction.
In a regular simulator, you will have this data browser in which you can browse through the environment and also the RTL and if you select the MD monitor you will see inside the transaction called MD_ITEM which you can add to the waveforms.
So the name that you put here it will be the name that you will see in the data browser.
Once you enable the recording then you need to begin the transaction.
You do this by calling this begin_tr() function which is already available in all the UVM components.
You pass to this function, the item, so the transaction, and the stream name.
So the name here must be the same with the one that you used to create the transaction stream.
The simulation time at which you call this begin_tr() will influence the moment when this bubble will appear on the waveforms.
Next in our collect_transaction() task we sample the information at the beginning of the item.
Once we do this we can take an optional step and call this record() function of the item.
When you call this record() function, in the background the simulator will take the information that you want to be displayed in this bubble.
This step is not really mandatory, it's only useful if your simulation will end in the middle of a transaction.
If you don't call this record() here, then in the waveforms you'll not see any information displayed in that half bubble.
This is because by default the UVM library will record all that information at the end of the transaction.
After that, in our collect_transaction(), we are waiting for the item to end.
And this is the moment when we need to call another function called end_tr().
So, the simulation time when we call this function will influence the moment when this bubble ends on the waveforms.
This end_tr() function will also call this record() function.
So, this is why I told you that is not really necessary for you to also call this record() here.
The last thing that we need to do is to tell the UVM library to record this transaction information.
For this, we have two options.
Either, for example, from the test in the build_phase(), we can set in the UVM configuration database this recording_detail field to value UVM_FULL, and here we can target any component from our environment in which we have these transactions.
Or another alternative is to pass a command to the simulator, just like we did for the verbosity, we can pass this +uvm_set_config_int.
This command has three arguments.
The first one is the full name of the component in which we want to set this recording_detail.
So the second argument is the name of the field that we want to set.
And the third argument is the value, this 400 value actually corresponds to this UVM_FULL.
My preferred way is to use this command as this will allow me to enable the transactions without modifying the SystemVerilog code like in the first option.
You can read more about this feature of the UVM Library in the UVM Class Reference Manual.
Here you have several chapters in which you can find more information.
First, under Policies, you have this uvm_recorder section.
In here, you can read more about the API of this uvm_recorder class.
Here you can find information about these record_*() functions.
So we have here different record_*() functions based on the type of the field that we want to record.
Another section in which you can find more information is here under "Base Classes" you have this uvm_transaction.
In here you can find more details on the API of this uvm_transaction class.
And the last section that I want to show you is here under "Command Line Processor".
Here you'll find more details on this +uvm_set_config_int command.
Another source of information for you is this article that I wrote called Debugging Tip: Look At The Bubbles.
In this article I'm talking about how you can use the UVM transactions in order to see on the waveforms the sequences that you are starting in the test.
So you can take advantage of this feature not only with the item collected by the monitor but also with the item used by the driver or even with the sequences.
That's it for this tutorial.
We talked about what are the benefits of this UVM transaction.
We talked about how we can configure in our environment the UVM transaction.
And in the end I shown you where you can find more information about this very useful feature.
I hope everything was clear for you.
Thanks for watching and see you in the next tutorial.
Bye!
