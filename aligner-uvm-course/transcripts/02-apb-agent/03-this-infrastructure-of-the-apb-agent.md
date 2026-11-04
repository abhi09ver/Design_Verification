# This infrastructure of the APB agent

*Chapter: APB agent · source: attached*

Hi, my name is Christian Slav and in this tutorial we are going to code together this infrastructure of the app agent.
We will create the App Agent class.
We will declare the Verilog interface to connect to our duty, and we will also create a configuration class which will hold that interface.
Let's start from the practice project and click copy to copy the project in our working area.
Now the first thing that we will do we will create the APB package file.
So let's click new for all the agents we will use as a prefix CFS.
And then the name of the interface.
This is because when you create an agent and especially one for a standard protocol like APB, you will expect that the agent will be used in multiple projects in your company.
So this is why you don't want to make any reference to the duty that you verify in your agent.
Let's create the include protection.
Let's declare the package.
We already know from the previous tutorials that we have to include the UVM macro file and import the UVM package.
So let's do this.
Okay.
Let's save.
Let's include this APB package in our environment.
Package.
And let's import everything under the environment package.
Let's try to run to see if we did any mistakes in our code.
Okay.
Everything looks okay.
Now let's create the APB interface so we can connect it to our duty.
And this will be done in a new file CFS API from interface.
Now let's create the interface to get the signals part of the app interface.
We can look in two documents.
We can look in the aligner data sheet.
And the APB signals are this ones.
Or we can also look in the APB protocol specification under the signal description and APB signals.
We also get the same signals here.
Just pay attention that this document describes also other signals like p prod and p strobe that we don't really support in our duty.
First we will declare the clock and we will use the clock as an input to this interface, as the clock signal will never be driven by the environment.
The rest of the signals we will declare them as logic signals here.
One thing to pay attention to is the fact that our APB interface has this bus signal.
The data here and the address.
Now, the width of those signals is 16 for the address and 32 for the data.
But on the APB protocol this can vary.
Usually when you build such an agent, which can be reused throughout other projects in your company, you would want to make those values the width of the address and the width of the data as parameters to our interface.
But this will complicate our code quite a lot.
And for our first agent, we will actually use some defines declared up here.
And then we will use those defines throughout our agent.
Just pay attention to this aspect that when you are building an agent which will be reused in your company throughout other projects, that your agent should be as flexible as possible, and you can do this with parameters.
But for now let's go to those defines that I mentioned.
So I'm applying the same if not def technique for this.
Uh define.
This will allow me in the future to override the value of this defined in some other project if this will be the case.
So let's do the same for the other for the data width.
Now that we have these defines we can start coding all the signals.
First is the reset.
Next is the address.
Okay we finish coding all the signals.
Let's click save.
Now we should include this APB Interface in our package.
The interface cannot be under a package, so we'll have to include this, um, APB interface file outside our package.
Let's click save and see if everything compiles.
Everything looks okay.
Now let's instantiate this interface in our Testbench.
Let's go here.
Let's make this window a little bit bigger.
Now let's create here the instance of our APB interface.
Let's connect the clock.
Okay.
Now let's connect the signals of this interface to our duty here.
So let's take this APB IAAF name and put it here.
Okay.
Now, the only thing remaining is to handle this reset.
We no longer need this reset signal here.
We will use the one from the APB interface.
And we will use that one because we might want to have tests in which we also drive the reset.
So we will.
This is why we will use the reset from the APB interface.
And now we will have to replace the code which drives that initial reset to use the reset from our APB interface.
So it will be here here and here.
And we can delete this one.
Let's save and see if everything compiles.
All looks good.
Now we want to put the reference to our interface in the database.
We can do this here and we will use that UVM config db.
If you want to get more information about UVM config db class, you can go to the class reference manual, go to the table of contents to the chapter Configuration and Resources and then you can find here uvm config db.
To read more about this class.
Another source of information for this would be the user guide.
You can go to the Table of Contents to chapter four using verification components and then to Verification Component Configuration.
And then you have here some information available for you.
Let's get back to our code and put this app interface in the database.
So it will be something like UVM config db which has a parameter.
And remember that the parameter is the type of data that you want to put in the database.
So in our case it will be a virtual interface.
Then we call the set function.
The first argument is the context.
And the context should be a component.
But because we are now in the testbench, we don't have access to any component.
The Testbench is just a Verilog module, so it will be null.
Then it will be the path to our app agent and this will look something like this.
UVM test top as all the tests will have this name, then environment, then app agent.
We must make sure that when we instantiate the app agent, we will use this name.
Then the name with which we will put this virtual interface in our database.
So it will be visible from the virtual interface.
And then we pass the interface and that's it.
Let's click save and see if the code compiles.
Everything looks okay.
Now let's move forward with our agent.
Let's first create an app types file, in which we will define all the types that we will need for this agent.
So the first type that we will need is one for the virtual interface.
So let's do this.
Okay.
So we can use this type to specify a virtual interface.
Let's include this file.
Let's create here the code to include two other files.
So we will need the agent configuration Curation class.
And we will need also the agent.
Now let's create the file for the agent configuration class.
Whenever I'm creating an agent I'm coding the agent configuration class as an UVM component.
But just be aware that it's also a common practice to code the agent configuration class as an UVM object.
I prefer to make it a component because I can take advantage of some other stuff, like using the UVM phases, or whenever I have to use the UVM override, which is another feature of UVM.
When you are working with components, this is much easier.
So this is why I prefer to make the agent configuration class as an UVM component.
Now that we've added the mandatory code, let's declare the virtual interface.
And it's a good practice to make the virtual interface as a local variable.
So this will be accessed only by this class.
And then to access that local variable we can use getters and setters.
So let's do this.
Let's declare the getter and the setter.
Because we use a getter and setter for example, we can do a check in the setter to make sure that the virtual interface is only set once, and this is done like so.
And because our agent configuration class is a component, we can make use of the UVM phases.
And for example, we can check that just before the run phase starts.
The virtual interface is set by the user of this agent.
If it is not set, then we will trigger a fatal error.
If it is set then we will print a confirmation message.
So let's do this.
Okay, so at start of simulation phase we will check if the virtual interface is set or not.
If it is not set then we will trigger an error because definitely we will need the virtual interface in the run phase, which is the next phase after this one.
And if it is set correctly, then we simply print a configuration message and our target in this tutorial is to see this message being printed.
Now let's move to the app agent.
Here we can extend the app agent from UVM component, but we can also make use of another UVM class called UVM agent.
Now let's create the handler for the agent configuration class and then create an instance of it in the build phase.
Let's see if our code compiles.
Everything looks good.
Now let's create an instance of the APB agent inside our environment.
Let's see if we get that fatal error because we did not get the virtual interface.
Let's give it a try.
Okay.
We have one fatal error, and this one says exactly what we expected.
The APB virtual interface is not configured at start of simulation phase.
And this error comes from the APB agent config from here.
So let's fix this issue by setting this virtual interface in our agent.
And we can do this in the connect phase.
So let's try to do this.
Here we can use the get function from the uvm config db, and this is the signature of that function.
And notice that it returns a bit.
So we will get a one if the get was successful and we will get a zero if the get was not successful.
So let's make use of this and check if our get was successful or not.
So let's do this.
Okay, so we printed a message.
Now please be aware that the Get actually puts the information retrieved from the database in its fourth argument.
So we need to declare here a virtual interface to use as the fourth argument.
So let's do this.
We put this one here.
And now if the get from the database fails, we will print this error message.
Else we need to set this in the Agent configuration class.
Okay.
Let's see if our code runs correctly and we get that confirmation message.
Okay.
We did not receive any fatal errors.
And now our confirmation message is printed here.
The APB virtual interface is configured at start of simulation phase.
So our code run correctly.
Now we have an agent which is connected to the interface to the APB um interface.
And in the next tutorials we will learn how to drive and to monitor this interface.
Thanks for watching and see you in the next tutorial.
Bye.
