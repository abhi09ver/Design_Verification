# Basic infrastructure that we need in order to develop the full verification

*Chapter: Course introduction · source: attached*

Hi, my name is Christian Slav and in this tutorial we are going to code together the basic infrastructure that we need in order to develop the full verification environment.
So we will build um, the Testbench with the basic testing site and the test will have an empty environment.
And also the Testbench will have an instance of the dot, the aligner to code.
Um, all this we will use as a development platform, this website, EDA playground.
And this allows us to build small systemverilog projects and to run them using different tools from different vendors like cadence, mentor, Synopsys, and so on.
If you're not familiar with this website, um, the first thing that you will have to do is to create an account.
And you can do this by going to this, uh, login page.
And in here you must register for a full account.
When you registering for a full account, You are not allowed to use a freely available email, because they will not give you access to some of the licenses for the tools that we will use.
So you cannot use here your Gmail, um, account or Yahoo account or stuff like this.
You will have to use something like, uh, the email from your school or the email from your work.
So with this, you will get access to the, uh, all the licenses.
Once you logged in, um, you can open the two, uh, links that I'm sharing with you.
So the first one, it's a link to the project called Environment Coding kickoff practice.
And this is the starting point for you to start, um, coding everything that we will learn in this tutorial.
And I put here for you the all the files of the aligner, um, here on the right and here on the left.
We will do all the coding.
If you don't want to code on your own, you can jump straight to the solution.
And this is the second project that I'm sharing with you environment coding kickoff solution.
And you will find here everything that we will code in this video.
But I strongly recommend for you to start from this practice project and do all the coding on your own.
Also, um, the last link that I want to share with you is the link to the um, UVM library.
So UVM is developed by this organization called um accelerator.
And in here you can find a useful information about UVM.
Um, we will develop the environment using the UVM 1.2 version.
Um, and you can find the documentation in here.
And the important stuff for us, it will be this class reference document and this user guide document.
Um, so the class reference is this one. and we will use it in this video to jump to some parts which are relevant for us.
And uh, this is the user guide, and it's a very useful document for you to, uh, get more details on UVM, but I'll let you, um, read on your own, uh, this document.
Now let's jump to coding.
Um, so the first thing is, um, that we will build is the testbench.
Let's bring again the picture of the Testbench, um, with all the stuff that we need to build inside.
So we will have to create this, uh, instance of the duty, uh, the clock generator, initial reset generator, and the logic to start UVM that runs this method.
So let's do this.
First, let's declare the testbench.
Okay.
This is a simple Verilog module.
And now let's create the instance of the duty, the top module of our aligner is this one CFS aligner V, which is this file.
And from here we can get the name of the module.
And this is this one.
So we will put it here.
And we will call it Dot.
And that's it.
This is the instance of our duty.
Now let's code the clock generator.
And to do this first we must declare the clock which is a red clock.
And then in an initial begin, first we initialize the clock to zero and then in a forever loop.
We need to change the clock every, let's say um, five nanoseconds.
So every five nanoseconds we change the clock in order to get a ten nanoseconds clock.
So this is the periods and the frequency will be 100MHz.
Now that we create the code to generate the clock, let's connect the signal to the input called um, the same thing, uh, clock uh clk from our, uh, duty.
So it's this one.
So let's do the connection here.
Like so.
Okay, so we finish with the clock generator.
Now let's do the something similar for the reset.
First we need to declare a signal called reset N because it is active low.
And then again in an initial begin block.
Uh, first we, um, set reset uh, to its inactive value, which is zero.
Then after, let's say six nanoseconds, we wait six nanoseconds and make reset active.
And at this point, all the registers from our duty will get their initial value.
Then we wait, let's say something like 30 nanoseconds and we make reset inactive again.
And the same thing.
We need to connect it to the input from our duty.
Let's make it like this and connect it here.
So this will be connected to this input wire called reset.
Let's align a little bit the um signals.
Okay.
Now let's um start our oven.
So it will be an initial begin.
And, and then, uh, we will have to call here the function called Run test, and we said that we want to call this with an empty string.
Um, if you did not click copy, let's do it now.
So this by clicking here, we, uh, this will copy this project to, uh, your working area.
Uh, so now you can modify the file.
Uh, you also get a new button here save.
And you can find this project.
Uh, you can close this every time.
As long as the project is safe and you can go to playgrounds.
Um, and here, uh, this is a new copy of the project and everything that we coded so far.
It's saved.
Okay, let's try to run it.
So, um, to run this, make sure that under, uh, the languages you selected Systemverilog and Verilog as Testbench and design for UVM, you have selected this UVM 1.2.
And then for tools we will use cadence.
Um, and yeah, that's about it.
We simply, uh, press run and let's see if we the code compiles.
Okay.
It did not compile because, uh, it cannot find this run test function.
And this is because we did not give access to the code from the module to all the stuff from UVM.
Run test is, uh, defined under the UVM package, so we need to import it.
Import uvm pkg.
This is the name of the UVM package, and we import everything from there.
Now we should, uh, get rid of this error.
Let's see what the tool says.
Okay.
It compiled.
Okay.
Um, but it should give us another error.
Okay, so this is the report that we get at the end.
It's a report showing how many times these types of messages appeared.
So we got one info.
But the important stuff is that we got one fatal error, and the fatal error is reported here.
And the problem is that UVM could not instantiate any components.
So it needs that test to be specified either as a string here.
So here we can put the name of the test class, or we can specify it as an um plus test name argument.
And on this platform this plus UVM test name can be specified here.
Um, so let's um, let's do this now.
So we simply copy this one we specify here equal.
And our test will be named.
Let's uh, bring this inheritance tree here.
So we will create this test now.
Test rig access.
So we need to specify this name.
Um, there.
So let's put it here.
CFS aligner test rig access.
Of course, if we run now, we will get the same error because we did not yet, uh, declare this class.
So let's do this.
We will put all the tests in an, uh, systemverilog package, and we will put all the environment classes in a separate package.
So we will have two packages for the test and for the environment.
Let's create the test package.
You can press this button here.
And then we put here CFS aligner test pkg dot csv.
One thing about the uh prefix that we will use throughout this uh, training is this one.
And it's somehow like a standard in the industry and all the files and all the classes will have to have a prefix like a short name for the company, and then a shortening for the duty that you will have to verify.
And then, um, everything else.
Okay.
Let's create here now all the files that I strongly recommend you that you protect all your files um, from multiple includes.
And this is done using a simple, if not diff construct.
So this will look like this.
If not diff and then the name of the file in capital letters liner test pkg csv.
So if this define does not exist then we define it define it.
And then and if so um regardless of how many times this file will be included, um, all the code will be parsed from inside will be passed once, uh, when this define does not exist.
Okay.
And now let's create the package.
First a liner test pkg and then end package.
Okay so this is the package um, which will contain all the files, all the classes of our, uh, tests.
Let's save this one now, let's include the test package in our test bench.
So up here, uh, before the module declaration, we will do, uh, include and then the name of the file.
And in order for UVM to, uh, have access to the test classes, we also have to import everything that we will declare under this, uh, package here.
Don't forget to add this line, because otherwise, uh, that run test function will not have access to all the tests.
Okay, now in here we know that we will have to create two, um, classes.
Um, we will have to create.
Let me bring this picture again.
We will have to create the test rig access and the test base.
And, um, I remind you that, uh, under the test base, we will create the instance of our environment in order to declare it only once.
And then, uh, we will use this, uh, class as a pattern for all our, uh, tests.
So let's do this.
Uh, let's put it here include, and then it will be CFS liner test base dot csv.
And we will declare this file, um, in just a couple of minutes and then test rig access.
Now let's create the test base CFS aligner test based create and let's create.
Now the second one create file here.
Okay.
Uh, let's make this window a little bit bigger okay.
Here again the same protection.
Test base is fi.
So if this is not defined we will define it here.
And if so this one will be uh we will declare the base class.
So it will be class CFS aligner test base, which extends from UVM test and class.
Now, um, in order to be able to extend from UVM test.
We need to get, um, the test package access to UVM.
So we will have to go here in the package and do something like import, UVM, PG, and everything from there.
Okay.
And, uh, so if you want to read more about this UVM test class this one inherits from UVM component, you can actually go to the, uh, class reference and then go to um in the table of contents, um, you can go to um, components maybe, and you can find this UVM test here and you can read more about this class.
Uh, okay.
And now in all the UVM components, uh, classes that you will declare, you will have to put some mandatory code in order for UVM to work.
And, uh, this is the mandatory code that you will have to put in all your components.
You will have to call this macro UVM component utils.
And this gives us access to some of the features of the UVM.
So this UVM component fields macro has this one argument.
And the argument needs to be the name of the class that you declared.
If you want to read more about this UVM component totals, again, you can go to the class, um reference manual.
Um, go to the menu and then you have this sections about macros.
And you can find that one under Component and Objects uh sections.
And in here uh, you will get access to um, some description about all the UVM component, uh, of all the macros and in particular this UVM component totals.
In order to have access to these component totals macros, we will have to include another file.
And this one is uh, like this one include.
It is called um UVM macros dot csv.
So um, in this file that we uh, include um, in this file, um, all the UVM macros are defined, um, including this one.
Okay.
Let's click save.
And now, uh, to finish with the mandatory code for all the components, we we will also have to declare a constructor with a given signature.
So to declare the constructor we do like this function new.
And then here um, the first argument uh mandatory here is the name uh which is of type string.
So this will be the name of the instance of this class, and then the second one is the parent of this component.
UVM component parent.
And then you also have to call a super.
Dot new and with the same arguments name and parent and class.
So this is the, uh, mandatory code, um, that you will have to put in all the classes.
Uh, let's save and let's go to this ridge axis.
Let's try to do, do that.
Very dangerous copy paste.
Put it here and make sure that we replace everything.
So ridge axis like this I need to be so the same here and here.
Ridge axis.
Be very careful when you do this copy paste stuff because it's a very common, um, source of errors.
Okay.
So we also declare, uh, direct access.
And the last thing here is that, uh, we, uh, have to make this array access inherit from the test base.
So don't forget to do this.
Okay, now let's see if our, uh, code compiles.
Okay, maybe we made some mistake.
Okay.
We did.
Um, let's see what was the problem in this base N class?
There is a problem with N class here.
Let's see if we spot the problem.
Uh, it's end function and function here.
And because we did that, uh, copy paste, we actually also carried, uh, the problem and function.
But now we fixed it.
Okay.
It compiled.
Okay.
This time, let's see if we get any fatal errors.
So we don't get any fatal.
We don't get any errors.
And now we have two UVM info messages and running tests.
So everything looks okay now.
Okay, uh, let's do the last part where we declare the, uh, environment package again.
A new file, cfs liner pkg.
This time create again the same protection.
If not f.
K g dot s fi.
So if that is not defined, we define it here and in here.
And if we declare the package CFS not PG.
Okay.
And in here, we already know that we will need to import UVM and everything from there.
And we also need to, uh, include that uh, UVM macros dot csv h uh, we will probably notice that we include this multiple times.
It's okay.
Um, this makes our packages, uh, let's say more independent.
And also this UVM macros file is protected by, uh, the same construct here.
And in here, uh, we know that we will have to include a file cfs aligner env dot csv.
Okay, save.
And then here we declare, uh, this environment File liner NTSB.
CFS a liner and dot is V.
So if this is not defined we define it.
And then in here we declare the class uh cfs a liner.
And so this will be our environment class which extends from UVM env and class.
And this UVM env.
It's some other uh base class from UVM which should be used uh, to uh, to be the parent for all the environment classes that we you declared.
Let's copy paste this mandatory code and replace the argument here.
Save.
And now let's include this, uh, CFS aligner liner package under our test package.
So let's include.
A spy.
And then we need to give the test access to the environment package.
And then we do like this.
Click save.
Let's run to see if we have any compilation errors okay.
Everything compiled okay.
Uh, now let's go to the test space and create that instance of the environment.
And we do this like this.
So we declare the handler here, uh, a liner n n.
And now to create, uh, this instance, we need to do this in the build phase of, uh, our test.
And we simply do this virtual function void Avoid.
The function associated with the build phase is called build phase and function.
All the phases will have to have one argument and this is UVM phase.
Phase for the build phase is mandatory that you call a super dot build phase.
So UVM will work properly.
And again we pass the same argument.
And now to create the instance of the environment this is done like so.
You can also call the uh directly the constructor.
But this is not the recommended way.
In UVM you make use of some static fields, uh, from uh, this environment.
And uh, in the environment there will be a static field called type ID and then here it will be a function called create.
And this function again has two arguments.
Uh, just like the constructor.
The first one is the name.
And you should put here the, uh, a string with the same value as the name here is not mandatory.
You can put here anything you want, but it's a good practice to use, um, the same name here as here.
And then you specify the parent and the parent of the.
Our environment is the test class.
Okay.
Now click save and then run.
Okay.
It compiled okay.
And it ran okay okay.
Now let's do some stuff in the read access.
And you can put the code that you want to be executed in your test in the run phase task, right in the, um, our run phase.
So we do this like this Virtual task run phase.
Remember, the run phase is a task again.
It has the same argument here.
Phase and task.
Now for UVM, you specify when you want your test to be ended using an objection mechanism.
This objection mechanism is quite simple.
You can view it as a counter.
Whenever you raise an objection, you increment that counter.
Whenever you drop an objection, you decrement that counter and UVM will stop the simulation.
When that counter is decremented to value zero and to make use of that mechanism, you do it like this.
So in the phase, um, object you call a function called raise objection.
And you can do something like there are two arguments this and the string test done.
So you raise an objection for the test done.
And to increment that counter and to decrement it, you drop the objection drop.
Okay.
Now in here, let's put some messages to put some to print some messages.
You can either use the dollar display which is a function which is native to systemverilog.
But you can actually make use of another macro from UVM.
And this one is uh, like so UVM info.
And this one has three arguments an ID, which is a string you can put here anything you want debug.
And then the message that you want to be printed, start of test and then some verbosity.
You can have different levels of verbosity like uh none Low.
Medium.
High.
Um, full and debug, I think, to control, um, whatever you want to be printed.
In our case, we will use UVM low.
So this is the start of simulation.
Let's put like an end of simulation and then let's make the simulation 100 nanoseconds.
Let's click save and then run.
Now the printed messages are here.
So at time zero we got this start of test which is this one.
And at time 100.
Uh, so after 100 nanoseconds we got this message end of test.
Now it would be very interesting to be able to see the waveforms.
And in order to see the waveforms, we have to do two things in our test bench.
Um, Before the run test.
We can put some code here.
Dump file in order to specify the name of the files in which you want your your waveforms to to be dumped.
So this will be dump VCD dump vars okay.
Click save and then you must select this options option under Tools and Simulation Simulators.
Right.
So from here you have to select open um EP wave after run.
Let's click this one uh save and then run.
And with uh, these two things done in our project, once the simulation finishes, there will be a pop up window like this one with, uh, in which we can add the waveforms.
So, um, let's close this one and go to this get signals.
And in here you have access to all the modules and submodules.
And what it's interesting from for us is this dot instance.
And from here, for example, we can put the clock up and select it.
We can put the reset this one um, and uh, yeah.
You can add here whatever signals you want.
Let's close this one.
But for now we actually made the logic to drive those signals.
So you can see the clock, uh, changing uh every five nanoseconds.
And you can also see the reset going, uh, to its active, uh, value at six nanoseconds and, uh, staying active, um, all the way up to 36 nanoseconds.
Okay.
So that's about it.
Uh, we implemented everything that we wanted, um, in this video.
Hope it was clear for you.
Thanks for watching.
And see you in the next video.
Bye.
