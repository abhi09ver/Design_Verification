# MD master driving logic

*Chapter: MD agent · source: attached*

Hi, my name is Christian Slav and in this tutorial we are going to talk about the MD master driving logic.
This is our current state of the environment with all the components that we implemented so far.
And in this tutorial we are going to talk about these ones, the sequencer and the driver from the MD Master agent.
When it comes to driving, the first thing that we need to figure out is what information we need to put in the item, which will be used by the driver in order to put information on the bus.
And in order to achieve this, just like for the APB, we need to look on how the MD transaction looks like on the waveforms.
First, we will need some pre and post drive delay to control the space at the beginning and at the end of an MD transaction.
Then the obvious candidates are the data offset and size.
And if we use these fields, then this means that the class definition in this case will look something like this.
We will have these three fields and the class must have as a parameter the data width.
But having the data width as a parameter for the item poses a problem.
Because the item stays outside the agent, we create the item in the sequences, and the sequences live outside our MD agent.
So this means that we need to specify a correct value for the data within the sequences, and also in the environment where we created the instance for the MD agent.
And we have to try to avoid using redundant information.
So in order to solve this problem, we can actually merge the data and size information into a list of bytes.
And in this way we can get rid of the data width parameter.
So with these two fields data as a list of bytes and offset, we can actually drive these three signals.
So the size will be the size of this list.
And the data that we drive.
We will take it from this list.
But all the information will be offset with this value here.
So in the end our item will have these four fields data offset pre drive delay and post drive delay.
Now let's try to think about how a sequence will look like in this case.
Just like for the app agent we will have this simple master sequence in which we will declare an item.
We randomize the item and then we send it to the driver via this UVM send macro.
But we will need to create some constraints to the information inside the item in order to derive correct information, and because in the item we have no knowledge about the data, we cannot apply the constraints there.
We need to apply them here in the sequence and let's see what constraints we should apply.
First of all, the data size must be bigger than zero because it makes no sense to send no data.
Next, we want the data size to be at most equal to the data width of the bus in bytes, because it makes no sense to try to send five bytes when our data bus is limited to four bytes, we want the same thing for the offset.
We don't want the offset to be bigger or equal to this data width in bytes.
And finally, there is a relationship between the data size and the offset.
So the sum of these two cannot be bigger than the data width in bytes, so it makes no sense to try to send four bytes starting from offset two, because there is no room to drive those four bytes starting from offset two.
This constraint is not clearly stated in the aligner specification, but we will apply it anyway because it makes sense.
But if you encounter such a scenario in a real life project, you should double check with the system architect and the designer to make sure that your assumption is correct.
As you probably noticed in these constraints, I made use of this function get data width from the sequencer.
So we need to create our sequencer class and we need to define this function inside.
But pay attention that there is a trick here in order to have this Getdata width function implemented in the sequencer.
The sequencer needs to be aware of the data width that we are using.
So this means that the sequencer class must have as a parameter that data width.
But this sequencer is actually created via that macro UVM declare sequencer in which we specify the type, and if we must specify the type of the sequencer, then we must also specify the value of the parameter.
And we really must avoid this, because then it makes no sense for us to go on this road with the data modeled as a list of bytes.
So let's try to figure out how we can define the sequencer type in order to have access to this get data with function, but still do not specify that data with parameter.
So let's say that the sequencer class is this one cfs SMD sequencer master, and this must inherit from UVM sequencer.
And the value of this request parameter must be the type of our item.
And just to clarify this notation here, this means that we are using this value for this parameter.
So this will be equivalent with writing this code.
We declare this class cfs MD Master Sequencer, which is this one which inherits from UVM sequencer, and it is using this value as the value of this request parameter.
So this is what we should understand by this notation.
But let's move forward.
So we want in our sequencer to have this function getdata width.
So let's add it also here in our diagram.
So as I said in order to implement this function and return the correct value we need our sequencer to have a parameter for the data width, but because we cannot declare this sequencer having this type as we want to avoid using this data width in our sequences, we need to create an intermediate class like this.
So we can have the CFS MD sequencer master base in which we declare this abstract function Getdata width.
And then we implement this function in CFS MD sequencer master, which has a parameter, and we make use of the polymorphism in the object oriented programming.
So our sequencer can be declared as this type.
And in this way we have access to this function.
But using the polymorphism we can access the implementation from this class.
So this is how we can specify the type of sequencer without specifying the data width, but still having access to this getdata width function.
And remember from the app agent that in the sequencer we still need to implement the reset logic, and because for the MD protocol, we also implement the slave aspect of the agent.
This means that we will have to duplicate the code inside this handle reset from the master base also here in the sequencer slave base.
But if you look carefully at the implementation of the handle reset from the app sequencer, you will notice that this has nothing to do with the protocol that we use or with the master or slave aspects.
So this means that we can merge these two classes into one single CFS MD sequencer class with a parameter to specify the type of the item that we want to drive, and in this way we declare the implementation of this handle reset only in one place.
So in the end, our P sequencer type will be actually this type.
CFS MD sequencer with a parameter.
And for the master this parameter will be this one.
And for the slave it will be this one.
Now let's try to figure out how the inheritance tree will look like for our sequences.
All the sequences will need to inherit from this UVM sequence.
And as for the APB agent, we will create this sequence base which will have this parameter item drive.
And in this sequence base we will declare this p sequencer.
And here is how the code will look like.
We will declare this p sequencer as of this type.
And then all the master sequences will inherit from this sequence base, but using as item drive this CFS MD item drive master.
So in our case, this simple master sequence will extend from this class.
So the important part for you to remember is this intermediate class that we will declare, in order to make use of the polymorphism, to have access to this getdata width.
Now moving on to the driver, um, of course our driver will need to inherit from UVM driver.
So we will have this CFS, MD driver master.
And again this one needs to have a parameter.
And of course we need to take into consideration that we will have to build a master and a slave driver.
And if you remember from the APB, the API of a driver will look something like this.
And of course, this will be quite similar between the master and the slave.
And if you remember from the APB driver, actually a lot of these have nothing to do with the protocol that we use.
This means that instead of duplicating the code in the master and in the slave, we can have an intermediate class called CFS MD driver, in which we declare and implement all common functions and tasks.
And we only declare this drive transaction task as an abstract task.
And then we create an implementation for it in the master and in the slave.
And one important thing to mention here, this drive transaction task, and also for the sequencer that get data with function will not be abstract functions.
Or in the case of systemverilog pure virtual functions, we will only declare them with an empty body and then implement them in the appropriate class.
This is because the UVM mechanism expects to be able to create an instance of this.
CFS, MD driver class, for example.
And if we would have declared this drive transaction as.
A pure virtual function, then this class should have been declared as a virtual class.
And this is not in line with the UVM library, but nevertheless, our code will work just fine if we declare this drive transaction as an empty task.
That's it!
For this tutorial, we talked about what information we need to put in this MD Master Driver item.
We talked about the inheritance tree of the MD sequencers and sequences, and we also talked about the inheritance tree of our MD drivers.
In the next tutorial we will implement all this together and hopefully everything will be clear for you.
Thanks for watching and see you in the next tutorial.
Bye!
