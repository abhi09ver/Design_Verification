# Coding the MD agent

*Chapter: MD agent · source: attached*

Hi, my name is Christian Slav and in this tutorial we are going to start coding the MD agent.
So we will build the interface, the agent configuration class and the agent for the MD agent.
So let's get started.
The starting point is the MD agent Infrastructure practice from the EDA playground.
So let's first copy it and let's resize the windows.
The first thing that we will create is the MD agent interface.
So let's create the file and start coding the signals.
So we said that the data width for the data signal will be a parameter not a defined.
So this is the parameter that we talked about.
And now we can use this parameter to declare local parameters for the offset width and for the size width.
And if we go to the aligner data sheet under the interface section, we can see that the documentation specifies what should be the width for the offset and for the size.
So for the offset will be this formula.
Maximum value between one and logarithm of data with divided by eight.
And for the size it will be logarithm of data width divided by eight plus one.
So let's code also this in our interface.
That's it.
Now we have parameters for the width of data offset and size signals.
And now let's simply declare the signals in the interface.
That's it.
Now let's create the MD agent package file in which we will include this interface.
That's it.
Now let's include the package file in the aligner package here.
And let's also import the MD package.
Now let's try to see if our code compiles.
So first let's make sure that we unselect show output file after run and then click run.
And let's make this um, window a little bit bigger to see the log.
So we have an error.
Let's fix it.
So it is in the MD interface.
We need to put here this sign.
Let's give it another try.
Everything compile successfully.
We don't have any errors.
Now let's go to our testbench and declare the two instances of this MD interface, one for the ADC side and one for the tick side.
And then we should connect those interfaces to our duty and put them in the UVM config db.
So let's do this.
That's it.
Now let's assign the reset signal to both of these interfaces.
And we can do this with a simple assign.
That's it.
Now let's connect these two interfaces to the signals inside the dot.
So first let's start with the MDX interface.
That's it for the ADC side.
Now let's do the same for the take side.
That's it.
So we connected all the signals of the MDX interface to these signals from the Dot starting with MDX.
And we did the same for the takes.
This.
The final thing that we have to do in the Testbench is to put these two interfaces in the UVM config db, just like we did for the APB interface.
So let's do this.
That's it.
We put these two interfaces in the database, and we put the MDX interface only to be accessible by the MDX agent.
And the same for the takes.
Next let's start coding the agent config class.
So first we will create this base class in which we will declare the fields that we also declare for the APB agent.
So the virtual interface active passive field has coverage and has checks.
And from this base class we will declare two subclasses, one for the slave and one for the master.
So let's start coding this.
So remember because the agent config will hold inside the interface which has a parameter, we also need this parameter inside the agent config.
And to make our life easier, let's declare here a typedef for the virtual interface and we should declare it here and not in some types file, because the type depends on the data width, which is only available here in the agent config.
Now let's go to our app agent config class and copy all those fields from there.
And simply change the type here.
And we don't need this one here.
Now let's call the UVM component param utils macro.
Let's take this code to initialize the fields.
And let's take the getters and setters.
And as you can see we are doing a lot of copy paste which is not the best approach.
It is very prone to error but we will fix this in future tutorials.
Let's search for the APB to see if we have this name here anywhere.
No.
So we are all good.
Now let's go to the interface and declare this hash checks field there, just like we did for the APB interface.
So it's this one.
That's it.
Now let's include our file in the package.
That's it.
Now one more thing that we have to do in the MBD package is import the UVM package.
That's it.
Now let's declare the includes for the slave and the master aspect of our MBD agent config class.
And now let's declare the agent config slave class.
That's it.
Now let's do the same thing for the master agent config class.
That's it.
Now let's give it a try to see if our code compiles and runs correctly.
Everything looks good.
We have no compilation errors so we can move forward.
Next we will have to create the agent class.
But before we do this, let's create that reset handler interface class in order to also code the reset logic inside our agent.
And this will be quite similar to the one declared under the APB.
So let's copy paste it from here.
That's it.
Now let's include the file.
Now let's create the MD agent class.
So first we will create this base class in which we declare and instantiate the agent config.
And from this one we will create the two subclasses for the slave and for the master.
So let's do this.
And because we will need to work with the interface to get it from the database, let's also create here this typedef that we you declared in the agent config class, also here in the agent.
And now let's go to the app agent and take as much code as possible from here.
So here is the app agent.
Um, let's make more room.
Let's take the agent config and change it to the appropriate type.
And from the app agent, let's take all this code and adapt it to our MD agent needs.
First, let's align it from the build phase.
We don't have the monitor yet, the coverage and the driver so we can get rid of this code so far.
So this will create the instance of our MD agent here.
And we here we should put the parameter data width.
And also here and our agent is a class width parameter, so let's use the param utils macro.
In the connect phase let's use the cfs MD interface.
We don't have yet this component, so let's remove them and we have the logic for the reset start reset end.
And we should declare these functions in the agent config.
So let's not forget this.
We have the handle reset function, which only needs to be changed here with MD, and then the run phase task in which we actually handle the reset.
Now let's go to the agent config and declare these two tasks with reset start and wait reset end.
And these should be quite similar to the ones we declared in the app package.
So we can take these two tasks from here from the APB agent config and put them in our MD agent config.
So we don't have p reset and we only have reset n here and here and here.
And we don't have p clock.
We only have clock.
That's it.
Let's try to run the code to see if everything compiles.
And let me double check if I include no.
So I do not include the agent.
Let's also do this.
Stop save.
And now I can resize this window and give it another try.
We have a compilation issue.
Let's fix it.
And I forgot here to replace the APB with the MD.
So let's do this.
So this is a big problem when we are doing this um copy paste.
That is quite a big chance that, um, we are going to do some, um, error.
We will forget to replace something.
Let's try to search for the APB.
And we still have here.
Let's search again.
And while we are here, I just realized that I have one mistake here.
I need to get rid of this virtual because MD is already a virtual interface.
And also, from the APB agent configuration class, I need to copy paste the code, which is checking that has checks field from the interface is not changed from there, but from the agent config.
So I need to copy this run phase from apb agent config and paste it in MD agent config here.
And we simply have to ensure that we don't have any APB word here.
Let's search.
Nothing here.
Okay, so we're all good, and we can try again to see if everything runs correctly.
But as I told you in the next tutorials where we learn some advanced techniques for coding UVM agents, we will develop a method to get rid of this copy paste that we do between the APB and the MD agent.
Okay.
Our code compiled.
We don't have any errors.
Now let's declare the slave and the master agents.
Now, the only thing that we need to do in the agent slave class is to call that set override function.
And we can do this in the constructor.
That's it.
So what this code does is the following.
It will replace all instances of cfs MD agent config with this type cfs MD agent config slave.
But it will do this for all the instances named agent config, under this component under agent slave, and in our case we only have one component which matches this criteria.
So it will be the agent config from our agent.
So the agent config is created with name agent config.
In this code, called under the constructor of the agent slave, it will be executed before the build phase of the agent, and this will force this create function here to return here an instance of type cfmd agent config slave.
Not this one.
Now let's include this agent slave and see if everything compiles.
We have an error.
Let's try to fix it.
We need to put here a semicolon.
And I notice that we also have here an issue we need to put here this sign.
Now let's do the same thing for the MD agent master.
And let's simply take this code and put it in the master.
That's it.
Now let's also include this file here.
That's it.
Now let's create the instances of our slave and master agents.
And we can do this in the environment.
That's it.
Now let's see if our code compiles and runs correctly.
Everything looks good.
We have no errors in our log.
Now, one thing that we have to pay attention when it comes to reusability is to avoid using the same numerical value over and over again, and in our case, we use this value 32 to define the width of the data for the MD interface we use it here and here and here and also in the test bench.
We use it in several places like here and here.
And what we can do is to create defines and parameters to hold this value for us.
And in this way we can specify this 32 value only in 1 or 2 places.
So let's try to do this.
Let's create a define file for the test package.
And in that file we will create a define for the aligner data width.
And then we will reuse that defined throughout our environment.
But we will only specify value 32 in only one place.
So let's do this.
That's it.
So we have this defined to keep the data width for the aid and Tex interface.
Now let's include this file.
And first let's use this define in the testbench.
And we can replace all these values here.
That's it.
Now in the environment.
In the aligner environment we also used this 32 value.
And we could also use here our define.
But because we are in a class it's better to use a parameter.
And this will make our environment more flexible.
For example there might be a system in which we want to instantiate two different aligner environments and with two different values for the width.
And we cannot do this with a define.
This is why it's better to use a parameter here.
So let's do this.
And here in the test base, we need to use the define to specify the parameter value for the environment.
That's it.
Now let's save and see if our code compiles correctly and runs.
Everything looks good.
We have no error in our log, and we managed to make our environment a bit more flexible using this define because we specified the width for the data bus for the Ericsson interfaces only in one place.
One more thing that we could have done, but we will not do this at this point is to actually create two defines, one for the add data width and one for the text data width, because this might be different, but we will deal with this in future tutorials.
That's it for this tutorial.
Thanks for watching and see you in the next tutorial.
Bye!
