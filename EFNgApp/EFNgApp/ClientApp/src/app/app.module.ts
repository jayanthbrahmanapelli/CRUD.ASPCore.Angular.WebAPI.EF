import { BrowserModule } from '@angular/platform-browser';
import { APP_ID, NgModule } from '@angular/core';
import { FormsModule, ReactiveFormsModule } from '@angular/forms';
import { HTTP_INTERCEPTORS, provideHttpClient, withInterceptorsFromDi } from '@angular/common/http';
import { RouterModule } from '@angular/router';
import { StoreModule } from '@ngrx/store';
import { AppComponent } from './app.component';
import { NavMenuComponent } from './nav-menu/nav-menu.component';
import { HomeComponent } from './home/home.component';
import { CounterComponent } from './counter/counter.component';
import { FetchDataComponent } from './fetch-data/fetch-data.component';
import { FetchEmployeeComponent } from './fetch-employee/fetch-employee.component';
import { AddEmployeeComponent } from './add-employee/add-employee.component';
import { employeeReducer, reducer } from './state/reducers/employee.reducer';
import { Employee } from 'src/models/employee';
import { EffectsModule } from '@ngrx/effects';
import { EmployeeEffect } from './state/effects/employee.effect';
import { StoreDevtoolsModule } from '@ngrx/store-devtools';
import * as fromEmployee from 'src/app/state/reducers/employee.reducer';

@NgModule({
  declarations: [
    AppComponent,
    NavMenuComponent,
    HomeComponent,
    CounterComponent,
    FetchDataComponent,
    FetchEmployeeComponent,
    AddEmployeeComponent
  ],
  imports: [
    BrowserModule,
    FormsModule,
    ReactiveFormsModule,
    StoreModule.forRoot({
      employee: reducer
    }),
    EffectsModule.forRoot([EmployeeEffect]),
    StoreDevtoolsModule.instrument({
      maxAge: 25,
      connectInZone: true
    }),
    RouterModule.forRoot([
    { path: '', component: HomeComponent, pathMatch: 'full' },
    { path: 'counter', component: CounterComponent },
    { path: 'fetch-data', component: FetchDataComponent },
    { path: 'fetch-employee', component: FetchEmployeeComponent },
    { path: 'register-employee', component: AddEmployeeComponent },
    { path: 'employee/edit/:id', component: AddEmployeeComponent },
], {})
  ],
  providers: [
    { provide: APP_ID, useValue: 'ng-cli-universal' },
    provideHttpClient(withInterceptorsFromDi())
  ],
  bootstrap: [AppComponent]
})
export class AppModule { }
